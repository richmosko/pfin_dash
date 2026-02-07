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

## Some External Requirements
Running a (modified) external copy of this project will need a few external things set up:

### UV Installation
This project (and all of the connected projects) uses uv as a python and package
manager. It's fast and pretty idiot proof... which is perfect for my skill level.
- macOS: `brew install uv`
- Linux: `curl -LsSf https://astral.sh/uv/install.sh | sh`
- Windows: `powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"`

*This might not be needed until there is more frontend code*

### Environmental Variables
A `.env` file will need to get added to the project root directory `pfin_dash`.
This file contains environmental variables that the scripts use to define API Keys
and database connection variables. An example of this file sits in the root
directory as `sample.env` with non-valid entries.

*List of items TBD*

### Many Other Things
TBD: Update this a the infrastructure comes together

## Installation
TBD

## Usage
TBD

## Contributing
... Just me so far...

## License
MIT License

## Contact
TBD
