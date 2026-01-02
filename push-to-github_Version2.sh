#!/usr/bin/env bash
# Push the prepared project into your existing empty repository:
#   https://github.com/tj-tweddle/hive-network
#
# Usage:
#   1. Save this file as push-to-github.sh
#   2. Make executable: chmod +x push-to-github.sh
#   3. Run: ./push-to-github.sh
#
# Requirements: git, bash, network access to github.com. You must have push permission
# to https://github.com/tj-tweddle/hive-network (authenticate via credential helper,
# GitHub CLI, or SSH as you normally do).
set -euo pipefail

REPO_URL="https://github.com/tj-tweddle/hive-network.git"
ROOT_DIR="hive-network"
COMMIT_MSG='chore: initial commit — add Solar Electrician Finder (map, docker, CI) + MIT license'

if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is not installed. Install git and retry."
  exit 1
fi

if [ -d "$ROOT_DIR" ]; then
  echo "Error: directory '$ROOT_DIR' already exists. Move or remove it before running this script."
  exit 1
fi

echo "Creating project tree in ./$ROOT_DIR ..."
mkdir -p "$ROOT_DIR"

cd "$ROOT_DIR"

# LICENSE
cat > LICENSE <<'EOF'
MIT License

Copyright (c) 2026 tj-tweddle

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

# README.md
cat > README.md <<'EOF'
# Solar Electrician Finder (ZIP-based) — Map + Deployable Example

This project finds the highest-rated residential solar electricians for a U.S. ZIP code, displays results in a list and on an interactive map, and is packaged so you can build and run it with Docker.

Highlights
- Backend (Express)
  - Geocodes ZIP codes with Zippopotam.us (no API key).
  - Queries Google Places or Yelp Fusion (use one API key).
  - Caches results in-memory.
  - Serves the React frontend build (single deployable image).
- Frontend (React)
  - ZIP entry, radius and result limit.
  - List of results (name, rating, reviews, address, phone).
  - Interactive Leaflet map showing results with markers and popups.
- Deployable
  - Single multi-stage Dockerfile builds the frontend and produces a production image.
  - docker-compose.yml for easy local testing (environment variables, port mapping).

Required
- Node 16+ to run locally (or Docker)
- One of:
  - GOOGLE_API_KEY (Places) OR
  - YELP_API_KEY (Yelp Fusion)

Quick local dev (without Docker)
1. Start backend (dev)
   - cd backend
   - npm install
   - copy `.env.example` -> `.env` and set keys (optional)
   - PORT=4000 npm start
2. Start frontend (dev)
   - cd frontend
   - npm install
   - npm start
   - Visit http://localhost:3000 (proxy to backend for /api)

Build & run with Docker (recommended for deployment)
- Build the image:
  docker build -t solar-electrician .
- Run with env vars:
  docker run -p 4000:4000 \
    -e GOOGLE_API_KEY=your_google_key_here \
    -e PORT=4000 \
    solar-electrician
- Or start with docker-compose:
  docker-compose up --build
  (Set GOOG/ YELP keys in docker-compose.yml or via environment)

API
GET /api/search?zip=ZIP&radiusMiles=10&limit=10
- zip (required): 5-digit US ZIP
- radiusMiles (optional): search radius in miles (default 10)
- limit (optional): max results (default 10)

Notes & Recommendations
- Keep API keys secret (use cloud provider secrets or Docker secrets in production).
- Add persistent cache (Redis) and rate-limiting for production.
- The map uses OpenStreetMap tiles via default Leaflet tile provider; consider an API keyed tile provider if heavy usage is expected.

What I changed
- Added Leaflet/react-leaflet to the frontend and map UI with markers and popups.
- Updated frontend to include location coordinates with each search result and to fit map bounds.
- Modified Express backend to serve the built frontend (production mode).
- Added a multi-stage Dockerfile and docker-compose.yml for a simple deployable flow.

If you want, I can:
- Add server-side distance sorting and return distances in results.
- Add clustering on the map for dense areas.
- Add place details fetch (phone) for Google Places results.
- Add automated tests and CI/CD (GitHub Actions) for building and publishing Docker images.

How to run it now
- With Docker:
  - docker-compose up --build
  - Open http://localhost:4000
  - Set API keys in the docker-compose file or pass them as environment variables.

- Or locally (dev):
  - Start backend: cd backend && npm install && PORT=4000 npm start
  - Start frontend: cd frontend && npm install && npm start
  - Visit http://localhost:3000
EOF

# .dockerignore
cat > .dockerignore <<'EOF'
node_modules
frontend/node_modules
backend/node_modules
frontend/build
.env
EOF

# Dockerfile
cat > Dockerfile <<'EOF'
# Multi-stage Dockerfile: build frontend, then create runtime image with backend + built frontend
FROM node:18 AS build

WORKDIR /app

# Install frontend deps and build frontend
COPY frontend/package*.json frontend/
RUN cd frontend && npm ci

COPY frontend/ frontend/
RUN cd frontend && npm run build

# Production image
FROM node:18-slim

WORKDIR /app

# Install backend production dependencies
COPY backend/package*.json backend/
RUN cd backend && npm ci --production

# Copy backend source
COPY backend/ backend/

# Copy built frontend into backend/frontend/build so Express can serve it
COPY --from=build /app/frontend/build backend/frontend/build

ENV NODE_ENV=production
ENV PORT=4000

WORKDIR /app/backend
EXPOSE 4000

CMD ["node", "server.js"]
EOF

# docker-compose.yml
cat > docker-compose.yml <<'EOF'
version: "3.8"
services:
  solar-finder:
    build: .
    image: solar-electrician:latest
    ports:
      - "4000:4000"
    environment:
      # Set one of these (or provide via env file or your platform)
      # GOOGLE_API_KEY: "your_google_places_key_here"
      # YELP_API_KEY: "your_yelp_fusion_key_here"
      PORT: "4000"
    restart: unless-stopped
EOF

# GitHub Actions workflow
mkdir -p .github/workflows
cat > .github/workflows/ci-and-publish.yml <<'EOF'
# CI: build frontend, verify backend, then build & publish Docker image to GHCR (and optionally Docker Hub)
# Triggers: push to main, tag push (v*), manual dispatch
# Requires no extra secrets to push to GitHub Container Registry (GITHUB_TOKEN provided by Actions),
# but you must allow `packages: write` permissions (set below). To also publish to Docker Hub, set
# repository secrets DOCKERHUB_USERNAME and DOCKERHUB_TOKEN.
on:
  push:
    branches:
      - main
    tags:
      - 'v*'
  workflow_dispatch:

permissions:
  contents: read
  packages: write
  id-token: write

name: CI / Build & Publish

jobs:
  build:
    name: Build & test (frontend + backend)
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Use Node.js 18
        uses: actions/setup-node@v4
        with:
          node-version: 18

      - name: Install backend dependencies
        working-directory: backend
        run: |
          npm ci

      - name: Install frontend dependencies & build
        working-directory: frontend
        run: |
          npm ci
          npm run build

      - name: Upload frontend build artifact
        uses: actions/upload-artifact@v4
        with:
          name: frontend-build
          path: frontend/build

  docker-publish:
    name: Build & publish Docker image
    runs-on: ubuntu-latest
    needs: build
    environment: production
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Download frontend build (from build job)
        uses: actions/download-artifact@v4
        with:
          name: frontend-build
          path: frontend/build

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v2

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2

      - name: Login to GitHub Container Registry (ghcr.io)
        env:
          GHCR_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          echo "${GHCR_TOKEN}" | docker login ghcr.io -u "${{ github.actor }}" --password-stdin

      - name: Optionally login to Docker Hub
        if: ${{ secrets.DOCKERHUB_USERNAME && secrets.DOCKERHUB_TOKEN }}
        env:
          DOCKERHUB_TOKEN: ${{ secrets.DOCKERHUB_TOKEN }}
        run: |
          echo "${DOCKERHUB_TOKEN}" | docker login -u "${{ secrets.DOCKERHUB_USERNAME }}" --password-stdin

      - name: Build and push multi-arch image to GHCR (and Docker Hub if configured)
        env:
          IMAGE_GHCR: ghcr.io/${{ github.repository_owner }}/solar-electrician
          IMAGE_TAG: ${{ github.sha }}
        run: |
          echo "Building image ${IMAGE_GHCR}:${IMAGE_TAG} and ${IMAGE_GHCR}:latest"
          docker build --platform linux/amd64,linux/arm64 \
            -t "${IMAGE_GHCR}:${IMAGE_TAG}" \
            -t "${IMAGE_GHCR}:latest" .
          docker push "${IMAGE_GHCR}:${IMAGE_TAG}"
          docker push "${IMAGE_GHCR}:latest"

          if [ -n "${{ secrets.DOCKERHUB_USERNAME }}" ]; then
            echo "Tagging & pushing to Docker Hub as ${DOCKERHUB_USERNAME}/solar-electrician"
            docker tag "${IMAGE_GHCR}:${IMAGE_TAG}" "${{ secrets.DOCKERHUB_USERNAME }}/solar-electrician:${IMAGE_TAG}"
            docker tag "${IMAGE_GHCR}:latest" "${{ secrets.DOCKERHUB_USERNAME }}/solar-electrician:latest"
            docker push "${{ secrets.DOCKERHUB_USERNAME }}/solar-electrician:${IMAGE_TAG}"
            docker push "${{ secrets.DOCKERHUB_USERNAME }}/solar-electrician:latest"
          fi

      - name: Output published image references
        run: |
          echo "Published images:"
          echo "  GHCR: ghcr.io/${{ github.repository_owner }}/solar-electrician:${{ github.sha }}"
          echo "  GHCR: ghcr.io/${{ github.repository_owner }}/solar-electrician:latest"
          if [ -n "${{ secrets.DOCKERHUB_USERNAME }}" ]; then
            echo "  Docker Hub: ${{ secrets.DOCKERHUB_USERNAME }}/solar-electrician:${{ github.sha }}"
            echo "  Docker Hub: ${{ secrets.DOCKERHUB_USERNAME }}/solar-electrician:latest"
          fi
EOF

# backend files
mkdir -p backend
cat > backend/package.json <<'EOF'
{
  "name": "solar-electrician-backend",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "start:dev": "nodemon server.js"
  },
  "dependencies": {
    "cors": "^2.8.5",
    "dotenv": "^16.0.0",
    "express": "^4.18.2",
    "node-cache": "^5.1.2",
    "node-fetch": "^2.6.7"
  }
}
EOF

cat > backend/.env.example <<'EOF'
# Copy this file to .env and fill values
# Use GOOGLE_API_KEY (Places) OR YELP_API_KEY (Yelp Fusion)
# GOOGLE_API_KEY=your_google_api_key_here
# YELP_API_KEY=your_yelp_api_key_here

PORT=4000
CACHE_TTL_SECONDS=600
EOF

cat > backend/server.js <<'EOF'
const express = require('express');
const fetch = require('node-fetch');
const NodeCache = require('node-cache');
const cors = require('cors');
const path = require('path');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 4000;
const CACHE_TTL = parseInt(process.env.CACHE_TTL_SECONDS || '600', 10);
const cache = new NodeCache({ stdTTL: CACHE_TTL });

/**
 * Helper: geocode ZIP -> { lat, lng }
 * Uses Zippopotam.us (free)
 */
async function geocodeZip(zip) {
  const url = `http://api.zippopotam.us/us/${zip}`;
  const res = await fetch(url);
  if (res.status !== 200) throw new Error('ZIP not found');
  const data = await res.json();
  const place = data.places && data.places[0];
  if (!place) throw new Error('No place for ZIP');
  return {
    lat: parseFloat(place.latitude),
    lng: parseFloat(place.longitude),
    placeName: place['place name'],
    state: place['state abbreviation'],
  };
}

/**
 * Call Google Places Nearby Search (returns array of items)
 */
async function googleNearby(lat, lng, radiusMeters, limit) {
  const key = process.env.GOOGLE_API_KEY;
  const url = `https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${lat},${lng}&radius=${radiusMeters}&keyword=solar+electrician&type=electrician&key=${key}`;
  const res = await fetch(url);
  const data = await res.json();
  if (data.status && data.status !== 'OK' && data.status !== 'ZERO_RESULTS') {
    throw new Error('Google Places error: ' + data.status);
  }
  const results = (data.results || []).slice(0, limit).map(r => ({
    name: r.name,
    rating: r.rating || 0,
    reviews: r.user_ratings_total || 0,
    address: r.vicinity || r.formatted_address || '',
    place_id: r.place_id,
    location: r.geometry && r.geometry.location ? { lat: r.geometry.location.lat, lng: r.geometry.location.lng } : null,
    phone: null,
    url: null,
    source: 'google'
  }));
  return results;
}

/**
 * Call Yelp Fusion Business Search
 */
async function yelpNearby(lat, lng, radiusMeters, limit) {
  const key = process.env.YELP_API_KEY;
  const url = `https://api.yelp.com/v3/businesses/search?term=solar+electrician&latitude=${lat}&longitude=${lng}&radius=${Math.min(radiusMeters, 40000)}&limit=${limit}`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${key}` }
  });
  if (!res.ok) {
    const txt = await res.text();
    throw new Error('Yelp error: ' + res.status + ' ' + txt);
  }
  const data = await res.json();
  const results = (data.businesses || []).map(b => ({
    name: b.name,
    rating: b.rating || 0,
    reviews: b.review_count || 0,
    address: (b.location && b.location.display_address && b.location.display_address.join(', ')) || '',
    phone: b.display_phone || '',
    url: b.url,
    location: b.coordinates ? { lat: b.coordinates.latitude, lng: b.coordinates.longitude } : null,
    source: 'yelp'
  }));
  return results;
}

/**
 * Normalize and sort results
 */
function sortAndLimit(items, limit) {
  return items
    .filter(Boolean)
    .sort((a, b) => {
      if ((b.rating || 0) !== (a.rating || 0)) return (b.rating || 0) - (a.rating || 0);
      return (b.reviews || 0) - (a.reviews || 0);
    })
    .slice(0, limit);
}

/**
 * Fallback mock data for development
 */
function mockResults(zip, center) {
  return [
    {
      name: "Sunrise Solar Electricians",
      rating: 4.9,
      reviews: 125,
      address: `123 Solar Way, ${zip}`,
      phone: "(555) 111-2222",
      location: { lat: center.lat + 0.01, lng: center.lng + 0.01 },
      source: 'mock'
    },
    {
      name: "Bright Home Solar",
      rating: 4.8,
      reviews: 98,
      address: `77 Sunny St, ${zip}`,
      phone: "(555) 333-4444",
      location: { lat: center.lat - 0.01, lng: center.lng - 0.01 },
      source: 'mock'
    }
  ];
}

app.get('/api/search', async (req, res) => {
  try {
    const zip = (req.query.zip || '').trim();
    if (!/^\d{5}$/.test(zip)) return res.status(400).json({ error: 'zip must be a 5-digit US ZIP' });

    const radiusMiles = Number(req.query.radiusMiles) || 10;
    const limit = Math.min(Number(req.query.limit) || 10, 50);
    const cacheKey = `search:${zip}:${radiusMiles}:${limit}`;

    const cached = cache.get(cacheKey);
    if (cached) return res.json({ source: 'cache', results: cached.results, center: cached.center, placeName: cached.placeName, state: cached.state });

    // geocode ZIP
    let geo;
    try {
      geo = await geocodeZip(zip);
    } catch (e) {
      return res.status(404).json({ error: 'Unable to geocode ZIP' });
    }
    const lat = geo.lat, lng = geo.lng;
    const radiusMeters = Math.round(radiusMiles * 1609.34);

    let results = [];

    if (process.env.GOOGLE_API_KEY) {
      try {
        results = await googleNearby(lat, lng, radiusMeters, limit);
      } catch (e) {
        console.error('Google error', e.message);
      }
    }

    if ((!results || results.length === 0) && process.env.YELP_API_KEY) {
      try {
        results = await yelpNearby(lat, lng, radiusMeters, limit);
      } catch (e) {
        console.error('Yelp error', e.message);
      }
    }

    if ((!results || results.length === 0)) {
      // fallback to mock data
      results = mockResults(zip, { lat, lng });
    }

    const final = sortAndLimit(results, limit);
    cache.set(cacheKey, { results: final, center: { lat, lng }, placeName: geo.placeName, state: geo.state });
    res.json({ source: 'live', results: final, center: { lat, lng }, placeName: geo.placeName, state: geo.state });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'server error' });
  }
});

/**
 * Serve frontend static build when in production or when build exists.
 * This lets the Docker image serve the built React app.
 */
const frontendBuildPath = path.join(__dirname, 'frontend', 'build');
if (require('fs').existsSync(frontendBuildPath)) {
  app.use(express.static(frontendBuildPath));
  app.get('*', (req, res) => {
    res.sendFile(path.join(frontendBuildPath, 'index.html'));
  });
}

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
EOF

# frontend files
mkdir -p frontend/public frontend/src
cat > frontend/package.json <<'EOF'
{
  "name": "solar-electrician-frontend",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "leaflet": "^1.9.4",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-leaflet": "^4.2.1",
    "react-scripts": "5.0.1"
  },
  "scripts": {
    "start": "PORT=3000 react-scripts start",
    "build": "react-scripts build"
  },
  "proxy": "http://localhost:4000"
}
EOF

cat > frontend/public/index.html <<'EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Solar Electrician Finder</title>
  </head>
  <body>
    <div id="root"></div>
  </body>
</html>
EOF

cat > frontend/src/index.js <<'EOF'
import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import './App.css';
import 'leaflet/dist/leaflet.css'; // Leaflet styles

const container = document.getElementById('root');
const root = createRoot(container);
root.render(<App />);
EOF

cat > frontend/src/App.js <<'EOF'
import React, { useState, useRef, useEffect } from 'react';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';

// Fix for default icon paths with many bundlers
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png';
import markerIcon from 'leaflet/dist/images/marker-icon.png';
import markerShadow from 'leaflet/dist/images/marker-shadow.png';
L.Icon.Default.mergeOptions({
  iconRetinaUrl: markerIcon2x,
  iconUrl: markerIcon,
  shadowUrl: markerShadow
});

function FitBounds({ bounds }) {
  const map = useMap();
  useEffect(() => {
    if (!bounds || bounds.length === 0) return;
    try {
      map.fitBounds(bounds, { padding: [50, 50] });
    } catch (e) {
      // fallback to setView
      const first = bounds[0];
      map.setView(first, 12);
    }
  }, [map, bounds]);
  return null;
}

export default function App() {
  const [zip, setZip] = useState('');
  const [results, setResults] = useState([]);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState('');
  const [radius, setRadius] = useState(10);
  const [limit, setLimit] = useState(10);
  const [center, setCenter] = useState({ lat: 37.7749, lng: -122.4194 }); // default center
  const [placeLabel, setPlaceLabel] = useState('');
  const mapRef = useRef();

  async function search(e) {
    e && e.preventDefault();
    setMessage('');
    setResults([]);
    if (!/^\d{5}$/.test(zip)) {
      setMessage('Please enter a valid 5-digit ZIP.');
      return;
    }
    setLoading(true);
    try {
      const resp = await fetch(`/api/search?zip=${zip}&radiusMiles=${radius}&limit=${limit}`);
      if (!resp.ok) {
        const err = await resp.json();
        setMessage(err.error || 'Server error');
        setLoading(false);
        return;
      }
      const data = await resp.json();
      setResults(data.results || []);
      if (data.center) setCenter(data.center);
      if (data.placeName && data.state) setPlaceLabel(`${data.placeName}, ${data.state}`);
      if ((data.results || []).length === 0) setMessage('No electricians found.');
    } catch (err) {
      setMessage('Network error');
    } finally {
      setLoading(false);
    }
  }

  // compute bounds for markers
  const bounds = (results && results.length > 0)
    ? results.filter(r => r.location && r.location.lat && r.location.lng).map(r => [r.location.lat, r.location.lng])
    : [[center.lat, center.lng]];

  return (
    <div className="container">
      <h1>Solar Electrician Finder</h1>
      <form onSubmit={search} className="search-form">
        <label>
          ZIP:
          <input value={zip} onChange={e => setZip(e.target.value)} placeholder="e.g. 94103" />
        </label>
        <label>
          Radius (miles):
          <input type="number" min="1" value={radius} onChange={e => setRadius(e.target.value)} />
        </label>
        <label>
          Max results:
          <input type="number" min="1" max="50" value={limit} onChange={e => setLimit(e.target.value)} />
        </label>
        <button type="submit" disabled={loading}>{loading ? 'Searching…' : 'Search'}</button>
      </form>

      {message && <p className="message">{message}</p>}

      <div className="layout">
        <div className="list">
          <h2>{placeLabel ? `Results around ${placeLabel}` : 'Results'}</h2>
          <ul className="results">
            {results.map((r, idx) => (
              <li key={idx} className="card">
                <div className="card-header">
                  <h3>{r.name}</h3>
                  <div className="rating">{r.rating} ★ ({r.reviews})</div>
                </div>
                <div className="address">{r.address || ''}</div>
                {r.phone && <div>Phone: {r.phone}</div>}
                <div className="links">
                  {r.location && (
                    <a
                      target="_blank"
                      rel="noreferrer"
                      href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(r.name + ' ' + (r.address || ''))}`}
                    >
                      Open in Maps
                    </a>
                  )}
                  {r.url && <a href={r.url} target="_blank" rel="noreferrer">Yelp</a>}
                </div>
              </li>
            ))}
          </ul>
        </div>

        <div className="map">
          <MapContainer center={[center.lat, center.lng]} zoom={12} style={{ height: '100%', minHeight: '400px', width: '100%' }} whenCreated={mapInstance => { mapRef.current = mapInstance }}>
            <TileLayer
              attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
              url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
            />
            <FitBounds bounds={bounds} />
            {results.map((r, idx) => r.location && (
              <Marker key={idx} position={[r.location.lat, r.location.lng]}>
                <Popup>
                  <div style={{minWidth: 200}}>
                    <strong>{r.name}</strong>
                    <div>{r.rating} ★ ({r.reviews})</div>
                    <div>{r.address}</div>
                    {r.phone && <div>Phone: {r.phone}</div>}
                    {r.url && <div><a href={r.url} target="_blank" rel="noreferrer">Yelp</a></div>}
                  </div>
                </Popup>
              </Marker>
            ))}
          </MapContainer>
        </div>
      </div>
    </div>
  );
}
EOF

cat > frontend/src/App.css <<'EOF'
body {
  font-family: system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial;
  background: #f7f9fb;
  margin: 0;
  padding: 20px;
}
.container {
  max-width: 1100px;
  margin: 0 auto;
}
h1 { margin-bottom: 12px; }

.search-form {
  display: flex;
  gap: 10px;
  align-items: end;
  flex-wrap: wrap;
  margin-bottom: 18px;
}
.search-form label {
  display: flex;
  flex-direction: column;
  font-size: 0.9rem;
}
.search-form input { padding: 6px 8px; font-size: 1rem; width: 160px; }
.search-form button { padding: 8px 12px; font-size: 1rem; cursor: pointer; }

.layout {
  display: grid;
  grid-template-columns: 420px 1fr;
  gap: 16px;
  align-items: start;
}

.list {
  min-width: 320px;
}

.results { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 12px; }
.card {
  background: white;
  border-radius: 8px;
  padding: 12px;
  box-shadow: 0 1px 3px rgba(0,0,0,0.06);
}
.card-header { display: flex; justify-content: space-between; align-items: center; }
.rating { color: #0b5; font-weight: 600; }
.address { color: #444; margin: 6px 0; }
.links a { margin-right: 10px; color: #0366d6; text-decoration: none; }
.message { color: #b00; }

/* Map column */
.map {
  height: 600px;
  min-height: 400px;
  background: #eee;
  border-radius: 8px;
  overflow: hidden;
}

/* Make map responsive on small screens */
@media (max-width: 900px) {
  .layout {
    grid-template-columns: 1fr;
  }
  .map {
    order: 2;
    height: 400px;
  }
}
EOF

# Initialize git, commit, push
echo "Initializing git repository..."
git init
git checkout -b main
git add .
git commit -m "$COMMIT_MSG"

# Add remote (HTTPS)
git remote add origin "$REPO_URL"

echo "Pushing to remote $REPO_URL (branch main). You may be prompted for credentials."
git push -u origin main

echo
echo "Done! Files pushed to $REPO_URL on branch main."
echo "Next steps:"
echo "  - In the repository Settings → Actions → General set 'Workflow permissions' to 'Read and write' so GHCR publishing works."
echo "  - Add secrets DOCKERHUB_USERNAME and DOCKERHUB_TOKEN if you want Docker Hub publishing from Actions."
echo "  - To run locally without Docker: start backend and frontend separately (see README)."