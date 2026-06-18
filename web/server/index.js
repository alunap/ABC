import "dotenv/config";
import express from "express";
import cors from "cors";
import path from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";

const { Pool } = pg;

const app = express();
const port = Number(process.env.API_PORT || 5174);
const schema = process.env.PGSCHEMA || "public";
const table = process.env.PGTABLE || "argyll_birds";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const webRoot = path.resolve(__dirname, "..");
const distDir = path.join(webRoot, "dist");

app.use(cors());
app.use(express.json());

const pool = new Pool({
  host: process.env.PGHOST || "192.168.178.21",
  port: Number(process.env.PGPORT || 5433),
  database: process.env.PGDATABASE || "birds",
  user: process.env.PGUSER || "postgres",
  password: process.env.PGPASSWORD,
  max: 8,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000
});

let tableInfoPromise;

const aliases = {
  species: ["species", "common_name", "english_name", "taxon"],
  latin: ["latin", "scientific_name", "latin_name"],
  date: ["date", "record_date", "observation_date", "obs_date"],
  place: ["place", "location", "site", "locality", "location_name"],
  gridref: ["gridref", "grid_ref", "grid_reference", "os_grid_ref"],
  observer: ["observer", "recorder"],
  count: ["count", "raw_count"],
  lower: ["l", "lower", "lower_bound", "count_lower", "min_count"],
  upper: ["u", "upper", "upper_bound", "count_upper", "max_count"],
  censorType: ["type", "censor_type", "count_type"],
  latitude: ["latitude", "lat", "y"],
  longitude: ["longitude", "lon", "lng", "long", "x"]
};

const numericTypes = new Set([
  "smallint",
  "integer",
  "bigint",
  "decimal",
  "numeric",
  "real",
  "double precision"
]);

function quoteIdent(value) {
  return `"${String(value).replaceAll('"', '""')}"`;
}

function fullTableName() {
  return `${quoteIdent(schema)}.${quoteIdent(table)}`;
}

function pickColumn(columns, names) {
  const byLower = new Map(columns.map((col) => [col.column_name.toLowerCase(), col]));
  for (const name of names) {
    const match = byLower.get(name.toLowerCase());
    if (match) return match;
  }
  return null;
}

function isNumeric(col) {
  return col && numericTypes.has(col.data_type);
}

function colExpr(col) {
  return quoteIdent(col.column_name);
}

function numericExpr(col) {
  if (!col) return "NULL::double precision";
  if (isNumeric(col)) return `${colExpr(col)}::double precision`;
  return `NULLIF(regexp_replace(${colExpr(col)}::text, '[^0-9.\\-]', '', 'g'), '')::double precision`;
}

function textExpr(col) {
  return col ? `${colExpr(col)}::text` : "NULL::text";
}

function dateExpr(col) {
  return col ? `${colExpr(col)}::date` : "NULL::date";
}

function requireColumn(info, key) {
  const col = info.cols[key];
  if (!col) {
    const label = aliases[key]?.join(", ") || key;
    const err = new Error(`The table does not expose a usable ${key} column. Looked for: ${label}.`);
    err.status = 500;
    throw err;
  }
  return col;
}

async function getTableInfo() {
  if (!tableInfoPromise) {
    tableInfoPromise = (async () => {
      const result = await pool.query(
        `
          select column_name, data_type
          from information_schema.columns
          where table_schema = $1 and table_name = $2
          order by ordinal_position
        `,
        [schema, table]
      );

      if (result.rows.length === 0) {
        throw new Error(`Could not find table ${schema}.${table}. Check PGSCHEMA and PGTABLE in .env.`);
      }

      const cols = Object.fromEntries(
        Object.entries(aliases).map(([key, names]) => [key, pickColumn(result.rows, names)])
      );

      return {
        columns: result.rows,
        cols,
        expressions: {
          countValue: buildCountExpression(cols),
          locationLabel: buildLocationLabel(cols)
        }
      };
    })();
  }
  return tableInfoPromise;
}

function buildCountExpression(cols) {
  if (cols.lower && cols.upper) {
    return `case
      when ${numericExpr(cols.lower)} is not null and ${numericExpr(cols.upper)} is not null
        then (${numericExpr(cols.lower)} + ${numericExpr(cols.upper)}) / 2.0
      when ${numericExpr(cols.lower)} is not null then ${numericExpr(cols.lower)}
      when ${numericExpr(cols.upper)} is not null then ${numericExpr(cols.upper)}
      else null
    end`;
  }
  if (cols.lower) return numericExpr(cols.lower);
  if (cols.upper) return numericExpr(cols.upper);
  return numericExpr(cols.count);
}

function buildLocationLabel(cols) {
  const parts = [cols.place, cols.gridref].filter(Boolean).map((col) => `nullif(trim(${textExpr(col)}), '')`);
  if (parts.length === 0) return "NULL::text";
  return `coalesce(${parts.join(", ")})`;
}

function parseCsvParam(value) {
  if (!value) return [];
  return String(value)
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function limitParam(value, fallback, max) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return Math.min(parsed, max);
}

function buildFilters(info, query) {
  const where = [];
  const params = [];
  const add = (value) => {
    params.push(value);
    return `$${params.length}`;
  };

  const species = parseCsvParam(query.species);
  if (species.length > 0) {
    const col = requireColumn(info, "species");
    where.push(`${textExpr(col)} = any(${add(species)}::text[])`);
  }

  const locations = parseCsvParam(query.locations);
  if (locations.length > 0) {
    where.push(`${info.expressions.locationLabel} = any(${add(locations)}::text[])`);
  }

  if (query.from) {
    const col = requireColumn(info, "date");
    where.push(`${dateExpr(col)} >= ${add(query.from)}::date`);
  }

  if (query.to) {
    const col = requireColumn(info, "date");
    where.push(`${dateExpr(col)} <= ${add(query.to)}::date`);
  }

  return {
    clause: where.length ? `where ${where.join(" and ")}` : "",
    params
  };
}

function asyncRoute(handler) {
  return (req, res, next) => {
    Promise.resolve(handler(req, res, next)).catch(next);
  };
}

app.get(
  "/api/health",
  asyncRoute(async (_req, res) => {
    const info = await getTableInfo();
    const ping = await pool.query(`select count(*)::int as rows from ${fullTableName()}`);
    res.json({
      ok: true,
      table: `${schema}.${table}`,
      rows: ping.rows[0].rows,
      columns: info.columns
    });
  })
);

app.get(
  "/api/metadata",
  asyncRoute(async (_req, res) => {
    const info = await getTableInfo();
    const speciesCol = requireColumn(info, "species");
    const dateCol = info.cols.date;
    const countValue = info.expressions.countValue;
    const locationLabel = info.expressions.locationLabel;

    const [overview, species, locations] = await Promise.all([
      pool.query(`
        select
          count(*)::int as records,
          count(distinct ${textExpr(speciesCol)})::int as species_count,
          count(distinct ${locationLabel})::int as location_count,
          min(${dateExpr(dateCol)}) as min_date,
          max(${dateExpr(dateCol)}) as max_date,
          round(avg(${countValue})::numeric, 2)::float as mean_count
        from ${fullTableName()}
      `),
      pool.query(`
        select ${textExpr(speciesCol)} as value, count(*)::int as records
        from ${fullTableName()}
        where ${textExpr(speciesCol)} is not null
        group by 1
        order by records desc, value asc
        limit 500
      `),
      pool.query(`
        select ${locationLabel} as value, count(*)::int as records
        from ${fullTableName()}
        where ${locationLabel} is not null
        group by 1
        order by records desc, value asc
        limit 500
      `)
    ]);

    res.json({
      overview: overview.rows[0],
      species: species.rows,
      locations: locations.rows,
      columns: info.columns,
      detectedColumns: Object.fromEntries(
        Object.entries(info.cols).map(([key, col]) => [key, col?.column_name || null])
      )
    });
  })
);

app.get(
  "/api/options",
  asyncRoute(async (req, res) => {
    const info = await getTableInfo();
    const speciesCol = requireColumn(info, "species");
    const locationLabel = info.expressions.locationLabel;
    const speciesSearch = String(req.query.speciesSearch || "").trim();
    const locationSearch = String(req.query.locationSearch || "").trim();

    const speciesParams = [];
    const speciesWhere = [`${textExpr(speciesCol)} is not null`];
    if (speciesSearch) {
      speciesParams.push(`%${speciesSearch}%`);
      speciesWhere.push(`${textExpr(speciesCol)} ilike $${speciesParams.length}`);
    }

    const locationParams = [];
    const locationWhere = [`${locationLabel} is not null`];
    if (locationSearch) {
      locationParams.push(`%${locationSearch}%`);
      locationWhere.push(`${locationLabel} ilike $${locationParams.length}`);
    }

    const [species, locations] = await Promise.all([
      pool.query(
        `
          select ${textExpr(speciesCol)} as value, count(*)::int as records
          from ${fullTableName()}
          where ${speciesWhere.join(" and ")}
          group by 1
          order by value asc
          limit 100
        `,
        speciesParams
      ),
      pool.query(
        `
          select ${locationLabel} as value, count(*)::int as records
          from ${fullTableName()}
          where ${locationWhere.join(" and ")}
          group by 1
          order by value asc
          limit 100
        `,
        locationParams
      )
    ]);

    res.json({ species: species.rows, locations: locations.rows });
  })
);

app.get(
  "/api/summary",
  asyncRoute(async (req, res) => {
    const info = await getTableInfo();
    const speciesCol = requireColumn(info, "species");
    const dateCol = info.cols.date;
    const countValue = info.expressions.countValue;
    const locationLabel = info.expressions.locationLabel;
    const filters = buildFilters(info, req.query);

    const [summary, bySpecies, byLocation] = await Promise.all([
      pool.query(
        `
          select
            count(*)::int as records,
            count(distinct ${textExpr(speciesCol)})::int as species_count,
            count(distinct ${locationLabel})::int as location_count,
            min(${dateExpr(dateCol)}) as min_date,
            max(${dateExpr(dateCol)}) as max_date,
            round(sum(${countValue})::numeric, 2)::float as total_count,
            round(avg(${countValue})::numeric, 2)::float as mean_count,
            round(percentile_cont(0.5) within group (order by ${countValue})::numeric, 2)::float as median_count
          from ${fullTableName()}
          ${filters.clause}
        `,
        filters.params
      ),
      pool.query(
        `
          select ${textExpr(speciesCol)} as label,
            count(*)::int as records,
            round(sum(${countValue})::numeric, 2)::float as total_count
          from ${fullTableName()}
          ${filters.clause}
          group by 1
          order by total_count desc nulls last, records desc
          limit 12
        `,
        filters.params
      ),
      pool.query(
        `
          select ${locationLabel} as label,
            count(*)::int as records,
            round(sum(${countValue})::numeric, 2)::float as total_count
          from ${fullTableName()}
          ${filters.clause}
          group by 1
          order by total_count desc nulls last, records desc
          limit 12
        `,
        filters.params
      )
    ]);

    res.json({
      summary: summary.rows[0],
      bySpecies: bySpecies.rows,
      byLocation: byLocation.rows
    });
  })
);

app.get(
  "/api/timeseries",
  asyncRoute(async (req, res) => {
    const info = await getTableInfo();
    const dateCol = requireColumn(info, "date");
    const countValue = info.expressions.countValue;
    const filters = buildFilters(info, req.query);
    const grain = req.query.grain === "month" ? "month" : "year";

    const result = await pool.query(
      `
        select
          date_trunc('${grain}', ${dateExpr(dateCol)})::date as period,
          count(*)::int as records,
          round(sum(${countValue})::numeric, 2)::float as total_count,
          round(avg(${countValue})::numeric, 2)::float as mean_count
        from ${fullTableName()}
        ${filters.clause}
        group by 1
        order by 1
      `,
      filters.params
    );

    res.json({ rows: result.rows });
  })
);

app.get(
  "/api/locations",
  asyncRoute(async (req, res) => {
    const info = await getTableInfo();
    const countValue = info.expressions.countValue;
    const locationLabel = info.expressions.locationLabel;
    const lat = info.cols.latitude;
    const lon = info.cols.longitude;
    const filters = buildFilters(info, req.query);
    const limit = limitParam(req.query.limit, 250, 1000);

    if (!lat || !lon) {
      res.json({ rows: [], hasCoordinates: false });
      return;
    }

    const result = await pool.query(
      `
        select
          ${locationLabel} as label,
          avg(${numericExpr(lat)})::float as latitude,
          avg(${numericExpr(lon)})::float as longitude,
          count(*)::int as records,
          round(sum(${countValue})::numeric, 2)::float as total_count
        from ${fullTableName()}
        ${filters.clause}
        group by 1
        having avg(${numericExpr(lat)}) is not null and avg(${numericExpr(lon)}) is not null
        order by total_count desc nulls last, records desc
        limit ${limit}
      `,
      filters.params
    );

    res.json({ rows: result.rows, hasCoordinates: true });
  })
);

app.get(
  "/api/records",
  asyncRoute(async (req, res) => {
    const info = await getTableInfo();
    const speciesCol = requireColumn(info, "species");
    const dateCol = info.cols.date;
    const countCol = info.cols.count;
    const lowerCol = info.cols.lower;
    const upperCol = info.cols.upper;
    const observerCol = info.cols.observer;
    const locationLabel = info.expressions.locationLabel;
    const filters = buildFilters(info, req.query);
    const limit = limitParam(req.query.limit, 100, 500);

    const result = await pool.query(
      `
        select
          ${dateExpr(dateCol)} as date,
          ${textExpr(speciesCol)} as species,
          ${locationLabel} as location,
          ${textExpr(countCol)} as raw_count,
          ${numericExpr(lowerCol)} as lower_count,
          ${numericExpr(upperCol)} as upper_count,
          ${textExpr(observerCol)} as observer
        from ${fullTableName()}
        ${filters.clause}
        order by ${dateExpr(dateCol)} desc nulls last
        limit ${limit}
      `,
      filters.params
    );

    res.json({ rows: result.rows });
  })
);

app.use(express.static(distDir));

app.get("*path", (_req, res, next) => {
  res.sendFile(path.join(distDir, "index.html"), (err) => {
    if (err) next();
  });
});

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(err.status || 500).json({
    error: err.message || "Unexpected server error"
  });
});

app.listen(port, "127.0.0.1", () => {
  console.log(`Argyll bird counts API listening at http://127.0.0.1:${port}`);
});
