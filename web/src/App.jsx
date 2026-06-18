import { useEffect, useMemo, useState } from "react";
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis
} from "recharts";
import {
  Calendar,
  Database,
  FilterX,
  LineChart,
  Loader2,
  MapPin,
  RefreshCw,
  Search,
  Table2
} from "lucide-react";

const api = {
  metadata: () => fetchJson("/api/metadata"),
  summary: (params) => fetchJson(`/api/summary?${params}`),
  timeseries: (params) => fetchJson(`/api/timeseries?${params}`),
  locations: (params) => fetchJson(`/api/locations?${params}`),
  records: (params) => fetchJson(`/api/records?${params}`)
};

async function fetchJson(url) {
  const response = await fetch(url);
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload.error || `Request failed: ${response.status}`);
  }
  return payload;
}

function formatNumber(value, options = {}) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) return "—";
  return new Intl.NumberFormat("en-GB", options).format(Number(value));
}

function formatDate(value) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("en-GB", {
    day: "2-digit",
    month: "short",
    year: "numeric"
  }).format(new Date(value));
}

function toDateInput(value) {
  if (!value) return "";
  return new Date(value).toISOString().slice(0, 10);
}

function useDebounced(value, delay = 250) {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const timeout = window.setTimeout(() => setDebounced(value), delay);
    return () => window.clearTimeout(timeout);
  }, [value, delay]);
  return debounced;
}

function App() {
  const [metadata, setMetadata] = useState(null);
  const [selectedSpecies, setSelectedSpecies] = useState([]);
  const [selectedLocations, setSelectedLocations] = useState([]);
  const [speciesSearch, setSpeciesSearch] = useState("");
  const [locationSearch, setLocationSearch] = useState("");
  const [fromDate, setFromDate] = useState("");
  const [toDate, setToDate] = useState("");
  const [grain, setGrain] = useState("year");
  const [summary, setSummary] = useState(null);
  const [timeseries, setTimeseries] = useState([]);
  const [locations, setLocations] = useState([]);
  const [records, setRecords] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [error, setError] = useState("");

  const debouncedSpeciesSearch = useDebounced(speciesSearch);
  const debouncedLocationSearch = useDebounced(locationSearch);

  useEffect(() => {
    let active = true;
    api
      .metadata()
      .then((data) => {
        if (!active) return;
        setMetadata(data);
        setFromDate(toDateInput(data.overview.min_date));
        setToDate(toDateInput(data.overview.max_date));
      })
      .catch((err) => {
        if (active) setError(err.message);
      })
      .finally(() => {
        if (active) setIsLoading(false);
      });
    return () => {
      active = false;
    };
  }, []);

  const filteredSpecies = useMemo(() => {
    const search = debouncedSpeciesSearch.trim().toLowerCase();
    const selected = new Set(selectedSpecies);
    const rows = metadata?.species || [];
    return rows
      .filter((item) => selected.has(item.value) || !search || item.value.toLowerCase().includes(search))
      .slice(0, 80);
  }, [metadata, selectedSpecies, debouncedSpeciesSearch]);

  const filteredLocations = useMemo(() => {
    const search = debouncedLocationSearch.trim().toLowerCase();
    const selected = new Set(selectedLocations);
    const rows = metadata?.locations || [];
    return rows
      .filter((item) => selected.has(item.value) || !search || item.value.toLowerCase().includes(search))
      .slice(0, 80);
  }, [metadata, selectedLocations, debouncedLocationSearch]);

  const params = useMemo(() => {
    const next = new URLSearchParams();
    if (selectedSpecies.length) next.set("species", selectedSpecies.join(","));
    if (selectedLocations.length) next.set("locations", selectedLocations.join(","));
    if (fromDate) next.set("from", fromDate);
    if (toDate) next.set("to", toDate);
    next.set("grain", grain);
    return next;
  }, [selectedSpecies, selectedLocations, fromDate, toDate, grain]);

  useEffect(() => {
    if (!metadata) return;
    let active = true;
    setIsRefreshing(true);
    setError("");

    Promise.all([
      api.summary(params),
      api.timeseries(params),
      api.locations(params),
      api.records(new URLSearchParams([...params.entries(), ["limit", "80"]]))
    ])
      .then(([summaryData, timeseriesData, locationData, recordsData]) => {
        if (!active) return;
        setSummary(summaryData);
        setTimeseries(
          timeseriesData.rows.map((row) => ({
            ...row,
            periodLabel: grain === "month" ? row.period.slice(0, 7) : row.period.slice(0, 4)
          }))
        );
        setLocations(locationData.rows);
        setRecords(recordsData.rows);
      })
      .catch((err) => {
        if (active) setError(err.message);
      })
      .finally(() => {
        if (active) setIsRefreshing(false);
      });

    return () => {
      active = false;
    };
  }, [metadata, params, grain]);

  const clearFilters = () => {
    setSelectedSpecies([]);
    setSelectedLocations([]);
    setSpeciesSearch("");
    setLocationSearch("");
    setFromDate(toDateInput(metadata?.overview?.min_date));
    setToDate(toDateInput(metadata?.overview?.max_date));
  };

  const hasFilters = selectedSpecies.length > 0 || selectedLocations.length > 0;

  if (isLoading) {
    return (
      <main className="app loading-shell">
        <Loader2 className="spin" size={28} />
      </main>
    );
  }

  return (
    <main className="app">
      <header className="topbar">
        <div>
          <p className="eyebrow">Argyll region</p>
          <h1>Bird Counts</h1>
        </div>
        <div className="connection">
          <Database size={16} />
          <span>{metadata ? "PostGIS connected" : "No connection"}</span>
        </div>
      </header>

      {error && (
        <section className="error-panel">
          <strong>Database query failed</strong>
          <span>{error}</span>
        </section>
      )}

      <section className="layout">
        <aside className="filters" aria-label="Filters">
          <div className="filter-header">
            <h2>Filters</h2>
            <button className="icon-button" onClick={clearFilters} aria-label="Clear filters" title="Clear filters">
              <FilterX size={18} />
            </button>
          </div>

          <SearchSelect
            title="Species"
            placeholder="Search species"
            search={speciesSearch}
            onSearch={setSpeciesSearch}
            options={filteredSpecies}
            selected={selectedSpecies}
            onSelected={setSelectedSpecies}
          />

          <SearchSelect
            title="Locations"
            placeholder="Search places or grid refs"
            search={locationSearch}
            onSearch={setLocationSearch}
            options={filteredLocations}
            selected={selectedLocations}
            onSelected={setSelectedLocations}
          />

          <div className="filter-group">
            <h3>
              <Calendar size={16} />
              Dates
            </h3>
            <label>
              From
              <input type="date" value={fromDate} onChange={(event) => setFromDate(event.target.value)} />
            </label>
            <label>
              To
              <input type="date" value={toDate} onChange={(event) => setToDate(event.target.value)} />
            </label>
          </div>

          <div className="filter-group">
            <h3>
              <LineChart size={16} />
              Time scale
            </h3>
            <div className="segmented">
              <button className={grain === "year" ? "active" : ""} onClick={() => setGrain("year")}>
                Year
              </button>
              <button className={grain === "month" ? "active" : ""} onClick={() => setGrain("month")}>
                Month
              </button>
            </div>
          </div>
        </aside>

        <section className="content">
          <div className="status-row">
            <div>
              <span className="muted">{hasFilters ? "Filtered records" : "All records"}</span>
              {summary?.summary?.min_date && (
                <span>
                  {formatDate(summary.summary.min_date)} to {formatDate(summary.summary.max_date)}
                </span>
              )}
            </div>
            <button className="refresh-button" onClick={() => setGrain((value) => (value === "year" ? "month" : "year"))}>
              <RefreshCw size={16} className={isRefreshing ? "spin" : ""} />
              Toggle grain
            </button>
          </div>

          <Summary summary={summary?.summary} />

          <section className="chart-grid">
            <Panel title="Counts over time" icon={<LineChart size={17} />}>
              <TimeSeriesChart data={timeseries} />
            </Panel>
            <Panel title="Location map" icon={<MapPin size={17} />}>
              <LocationPlot rows={locations} />
            </Panel>
          </section>

          <section className="chart-grid">
            <Panel title="Top species" icon={<Search size={17} />}>
              <RankingChart data={summary?.bySpecies || []} color="#197278" />
            </Panel>
            <Panel title="Top locations" icon={<MapPin size={17} />}>
              <RankingChart data={summary?.byLocation || []} color="#8a4f19" />
            </Panel>
          </section>

          <Panel title="Recent records" icon={<Table2 size={17} />}>
            <RecordsTable rows={records} />
          </Panel>
        </section>
      </section>
    </main>
  );
}

function SearchSelect({ title, placeholder, search, onSearch, options, selected, onSelected }) {
  const selectedSet = new Set(selected);
  const toggle = (value) => {
    if (selectedSet.has(value)) {
      onSelected(selected.filter((item) => item !== value));
    } else {
      onSelected([...selected, value]);
    }
  };

  return (
    <div className="filter-group">
      <h3>{title}</h3>
      <label className="search-field">
        <Search size={15} />
        <input value={search} onChange={(event) => onSearch(event.target.value)} placeholder={placeholder} />
      </label>
      <div className="option-list">
        {options.map((option) => (
          <label className="option-row" key={option.value} title={option.value}>
            <input
              type="checkbox"
              checked={selectedSet.has(option.value)}
              onChange={() => toggle(option.value)}
            />
            <span>{option.value}</span>
            <small>{formatNumber(option.records)}</small>
          </label>
        ))}
      </div>
    </div>
  );
}

function Summary({ summary }) {
  const tiles = [
    ["Records", summary?.records, {}],
    ["Estimated birds", summary?.total_count, { maximumFractionDigits: 0 }],
    ["Species", summary?.species_count, {}],
    ["Locations", summary?.location_count, {}],
    ["Mean count", summary?.mean_count, { maximumFractionDigits: 1 }],
    ["Median count", summary?.median_count, { maximumFractionDigits: 1 }]
  ];

  return (
    <section className="summary-grid">
      {tiles.map(([label, value, options]) => (
        <div className="metric" key={label}>
          <span>{label}</span>
          <strong>{formatNumber(value, options)}</strong>
        </div>
      ))}
    </section>
  );
}

function Panel({ title, icon, children }) {
  return (
    <section className="panel">
      <div className="panel-title">
        {icon}
        <h2>{title}</h2>
      </div>
      {children}
    </section>
  );
}

function TimeSeriesChart({ data }) {
  if (!data.length) return <EmptyState text="No records match the current filters." />;
  return (
    <div className="chart">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data} margin={{ top: 12, right: 18, left: 0, bottom: 8 }}>
          <defs>
            <linearGradient id="countFill" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor="#197278" stopOpacity={0.38} />
              <stop offset="95%" stopColor="#197278" stopOpacity={0.04} />
            </linearGradient>
          </defs>
          <CartesianGrid stroke="#d8dfdc" strokeDasharray="3 3" />
          <XAxis dataKey="periodLabel" tickMargin={8} minTickGap={22} />
          <YAxis width={54} tickFormatter={(value) => formatNumber(value, { notation: "compact" })} />
          <Tooltip formatter={(value, name) => [formatNumber(value), name === "total_count" ? "Estimated birds" : name]} />
          <Area
            type="monotone"
            dataKey="total_count"
            stroke="#197278"
            strokeWidth={2}
            fill="url(#countFill)"
            activeDot={{ r: 4 }}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}

function RankingChart({ data, color }) {
  const rows = data
    .filter((item) => item.label)
    .map((item) => ({ ...item, shortLabel: item.label.length > 24 ? `${item.label.slice(0, 23)}...` : item.label }))
    .reverse();

  if (!rows.length) return <EmptyState text="No ranking data available." />;

  return (
    <div className="chart">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={rows} layout="vertical" margin={{ top: 12, right: 18, left: 24, bottom: 8 }}>
          <CartesianGrid stroke="#d8dfdc" strokeDasharray="3 3" horizontal={false} />
          <XAxis type="number" tickFormatter={(value) => formatNumber(value, { notation: "compact" })} />
          <YAxis type="category" dataKey="shortLabel" width={116} tick={{ fontSize: 12 }} />
          <Tooltip
            formatter={(value, name) => [formatNumber(value), name === "total_count" ? "Estimated birds" : "Records"]}
            labelFormatter={(_, payload) => payload?.[0]?.payload?.label || ""}
          />
          <Bar dataKey="total_count" fill={color} radius={[0, 4, 4, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}

function LocationPlot({ rows }) {
  if (!rows.length) return <EmptyState text="No coordinate data available for this selection." />;

  const bounds = rows.reduce(
    (acc, row) => ({
      minLat: Math.min(acc.minLat, row.latitude),
      maxLat: Math.max(acc.maxLat, row.latitude),
      minLon: Math.min(acc.minLon, row.longitude),
      maxLon: Math.max(acc.maxLon, row.longitude),
      maxCount: Math.max(acc.maxCount, row.total_count || row.records || 1)
    }),
    {
      minLat: Infinity,
      maxLat: -Infinity,
      minLon: Infinity,
      maxLon: -Infinity,
      maxCount: 1
    }
  );

  const padding = 28;
  const width = 720;
  const height = 360;
  const lonRange = bounds.maxLon - bounds.minLon || 1;
  const latRange = bounds.maxLat - bounds.minLat || 1;

  return (
    <div className="map-shell">
      <svg viewBox={`0 0 ${width} ${height}`} role="img" aria-label="Observation locations by latitude and longitude">
        <rect className="map-bg" x="0" y="0" width={width} height={height} rx="8" />
        {[0.25, 0.5, 0.75].map((tick) => (
          <g key={tick}>
            <line
              className="map-grid"
              x1={padding}
              x2={width - padding}
              y1={padding + tick * (height - padding * 2)}
              y2={padding + tick * (height - padding * 2)}
            />
            <line
              className="map-grid"
              x1={padding + tick * (width - padding * 2)}
              x2={padding + tick * (width - padding * 2)}
              y1={padding}
              y2={height - padding}
            />
          </g>
        ))}
        {rows.map((row) => {
          const x = padding + ((row.longitude - bounds.minLon) / lonRange) * (width - padding * 2);
          const y = height - padding - ((row.latitude - bounds.minLat) / latRange) * (height - padding * 2);
          const radius = 4 + Math.sqrt((row.total_count || row.records || 1) / bounds.maxCount) * 15;
          return (
            <circle key={`${row.label}-${row.latitude}-${row.longitude}`} cx={x} cy={y} r={radius} className="map-point">
              <title>
                {row.label}: {formatNumber(row.total_count, { maximumFractionDigits: 0 })} estimated birds from{" "}
                {formatNumber(row.records)} records
              </title>
            </circle>
          );
        })}
      </svg>
    </div>
  );
}

function RecordsTable({ rows }) {
  if (!rows.length) return <EmptyState text="No records match the current filters." />;

  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Date</th>
            <th>Species</th>
            <th>Location</th>
            <th>Count</th>
            <th>Observer</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row, index) => (
            <tr key={`${row.date}-${row.species}-${row.location}-${index}`}>
              <td>{formatDate(row.date)}</td>
              <td>{row.species || "—"}</td>
              <td>{row.location || "—"}</td>
              <td>{row.raw_count || countRange(row)}</td>
              <td>{row.observer || "—"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function countRange(row) {
  if (row.lower_count === null && row.upper_count === null) return "—";
  if (row.lower_count === row.upper_count || row.upper_count === null) return formatNumber(row.lower_count);
  if (row.lower_count === null) return formatNumber(row.upper_count);
  return `${formatNumber(row.lower_count)}-${formatNumber(row.upper_count)}`;
}

function EmptyState({ text }) {
  return <div className="empty-state">{text}</div>;
}

export default App;
