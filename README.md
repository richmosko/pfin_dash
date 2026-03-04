# (pfin-dash) Personal Finance Dashboard

## Description
This project consists of a collection of frontend applications and plug-ins to visualize
personal finance items such as:
- Account Transaction Tracking
- Transaction Categorization
- Asset Categorization
- Budgeting Summaries
- Portfolio Valuations
- Asset Allocations
- Rebalancing Targets
- Portfolio Performance Tracking
- Cash Flow Tracking
- Tax Estimate Calculations
- Stock Screening & Valuation Heuristics
- Inflation Tracking
- Monte Carlo Simulations w/ cash flows for Retirement Planning

...This is a *personal project*. Not professional software. Mostly used as a learning vehicle,
and a way to automate much of what I'm already doing manually.

## Tech Stack
- **Frontend**: React + TypeScript + Vite
- **Backend**: Self-hosted Supabase (PostgreSQL + Auth)
- **Deployment**: Docker (Nginx) via Coolify

## Prerequisites
- [Node.js](https://nodejs.org/) (v22+)
- A running Supabase instance

## Setup
1. Clone the repo
2. Copy `.env.example` to `.env` and fill in your Supabase URL and anon key
3. Install dependencies: `npm install`
4. Run the SQL migration: `sql/migration/001_invite_codes.sql`
5. Start dev server: `npm run dev`

## Project Structure
```
sql/              # Database schema and migrations
src/
  components/     # Reusable UI components
  pages/          # Route-level page components
  lib/            # Third-party client setup (Supabase)
  hooks/          # Custom React hooks
  utils/          # Pure utility functions
  styles/         # Global CSS
```

## Deployment
Build and deploy via Docker:
```
docker build -t pfin-dash .
docker run -p 80:80 pfin-dash
```

## Contributing
... Just me so far...

## License
MIT License
