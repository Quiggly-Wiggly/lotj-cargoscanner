# LotJ Cargo Scanner

A Mudlet trade planner for Legends of the Jedi. Scan planet prices, compare
one-way routes and loops through 2–4 planets, and estimate profit for your cargo
capacity. Everything runs in a clickable, colored menu in the main console. Setup and scan
links fill the command line; review and press Enter. View links open directly.

## Install

1. Download `lotj-cargoscanner.mpackage`.
2. In your LotJ Mudlet profile, open **Package Manager**, choose **Install**, and
   select the file.
3. Connect to the game and type `cargoscan`.

Enable GMCP and load the galaxy map through the LotJ UI before scanning.
No Python installation or source files are needed to use the package.

To update, remove the old package in Package Manager and install the new file.
Saved prices and cargo capacity are retained.

## First run

Replace `1000` with your ship's cargo capacity:

```text
cargoscan cargocapacity 1000
cargoscan scan
```

Wait for the scan to finish. It displays ranked loops automatically. Click a
rank or type `cargoscan show 1` for the cargo, purchase cost, sale proceeds, and
profit on every leg.

## Commands

| Command | Action |
|---|---|
| `cargoscan` | Open the main menu |
| `cargoscan settings` | Change capacity, ranking, price age, and scan output |
| `cargoscan scan [planet]` | Refresh all planets, or one from your planet list |
| `cargoscan stop` | Stop scanning; keep completed prices |
| `cargoscan loops` | Compare two- and three-planet loops |
| `cargoscan loops 3` | Show three-planet loops; also accepts `2` or `4` |
| `cargoscan loops 3 25` | Show up to 25 three-planet loops |
| `cargoscan routes [count]` | Show one-way routes |
| `cargoscan show <number>` | Show a route's details |
| `cargoscan status` | Check fresh, stale, and missing prices |
| `cargoscan planets` | Browse planets; click one to refresh it |
| `cargoscan help` | Open the full command reference |

## How to read results

Profit is `(sell price - buy price) × cargo capacity`, **before tax and fuel**.
Loops include the return leg and assume a full load on every leg. Tax rates are
shown in details but are not deducted; cargo-tax calculations are unverified.
Prices may change before you trade.

Routes rank by profit per galaxy-map distance by default. Distance does not
include launch, landing, or cargo-transfer time. Use `cargoscan sort margin` to
rank by total profit instead.

GMCP supplies planet names and coordinates. If live planet data is unavailable,
the scanner uses the loaded LotJ UI galaxy map, which may be restored from its
cache. Live data takes priority when available. `showplanet "<planet>" resources`
supplies prices and tax rates. The scanner looks up prices only; it does not
fly your ship or trade cargo.

## Settings and troubleshooting

- Capacity and completed prices are saved in your Mudlet profile. Ranking,
  price-age limit, and scan output reset when the package reloads.
- Prices older than 60 minutes are excluded by default. Change the limit in
  Settings or with `cargoscan age <minutes>`.
- Compact scans hide recognized market output. Use `cargoscan output full` to
  see the original responses.
- Wait until scanning finishes before sending other game commands. Another
  command, an incomplete response, or a disconnect stops the scan. Retry with
  `cargoscan scan <planet>`.
- If the planet list is empty, load the LotJ UI galaxy map and click Refresh.
  `cargoscan diagnostics` shows which catalog is selected, the data type and
  system/planet counts for live GMCP and the UI map, and the saved-price location.
- The GMCP probe only records event names; it does not scan prices. A resource
  lookup can return text without any GMCP events. Use `cargoscan scan <planet>`
  (or another name from the planet list) to capture prices.

## Development

```sh
python3 scripts/build.py
python3 -m unittest discover -s tests -v
```

Python's standard library builds the root `lotj-cargoscanner.mpackage`; tests use
LuaJIT/Lua 5.1. No Python or Lua installation is needed by Mudlet users.
Sources are in `src/`; all test worlds, governments, and market fixtures are
fictional/synthetic. The repository and package contain no captured prices,
galaxy snapshots, character data, or investigation notes.

Version 0.4.0 keeps the scanner behavior and safe Windows saves, shortens help,
and makes setup/scan clicks prefill commands for review. Read-only menu links
open their views directly. Commands remain visible beside clickable labels.
Native visual checks are manual; tests cover console layouts and behavior using
simulated Mudlet APIs, including Windows file replacement failures.
