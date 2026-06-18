# Argyll Bird Counts Web App

Local React app and Node API for querying the `public.argyll_birds` PostGIS table.

## Setup

```sh
cd web
npm install
npm run dev
```

The React app runs at <http://127.0.0.1:5173>. The API runs at <http://127.0.0.1:5174>.

Database connection settings live in `.env`. The browser only talks to the local API; database credentials are not sent to the client.

## Production build

```sh
cd web
npm run build
npm start
```

After `npm run build`, `npm start` serves both the API and the compiled frontend from <http://127.0.0.1:5174>.
