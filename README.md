# hermas

A small collection of Python utilities and a Hermes Discord-gateway startup
script used in the OpenClaw sandbox.

## Contents

- `start-hermes.sh` — Bootstraps a local Hermes gateway (loads tokens from
  `openclaw.json` / `.env`, prepares `$HERMES_HOME`, and runs
  `hermes gateway run -v`).
- `ascii_art.py` — Generates several simple ASCII-art patterns
  (smiley faces, houses, …).
- `primes_calculator.py` — Computes all prime numbers from 1 to 1000 and
  writes them to `primes_1_to_1000.txt`.
- `weather_report.py` — Fetches tomorrow's weather for five Chinese cities
  via the free Open-Meteo API and prints a summary table; sample output is
  in `weather_report.txt`.

## Usage

Run any of the Python scripts directly:

```bash
python3 ascii_art.py
python3 primes_calculator.py
python3 weather_report.py
```

To start the Hermes gateway (requires `hermes`, a `hermes-agent` conda env,
and a valid `DISCORD_BOT_TOKEN`):

```bash
./start-hermes.sh
```

## License

[MIT](LICENSE)
