#!/usr/bin/env bash
# AM215 — 00_setup.sh
# Purpose: quick environment check and dataset download with minimal fuss.

# The "#!/usr/bin/env bash" line at the top is a called a "shebang"
# It tells the shell what program to run the script with.
# The file extension (.sh, .py) is just for human convenience.

# You'll see this line in many scripts.
# It just a saftey measure to make script exit on error/undefined variables
set -euo pipefail

echo "[setup] Checking for required Python packages (numpy, scipy, matplotlib, pandas)..."
# The > /dev/null pattern here is a common way of saying "don't show me the output"
if python3 -c "import numpy, scipy, matplotlib, pandas" >/dev/null 2>&1; then
  echo "[setup] OK: required packages already available."
else
  echo "[setup] Missing packages detected. Creating a virtual environment 'am215-venv' and installing them."
  python3 -m venv am215-venv
  # NOTE: a script cannot activate the venv for your current shell; we do installs explicitly,
  # and then print the command you should run to activate it for subsequent work.
  am215-venv/bin/pip install --upgrade pip
  am215-venv/bin/pip install numpy scipy matplotlib pandas
  echo "[setup] Installed packages inside venv."
  echo "[setup] To activate it in your current shell, run:"
  echo "  source am215-venv/bin/activate"
fi

# Ensure the target dir for data exists
mkdir -p raw
# wget: -O (capital O) sets the output file; -q for quiet + show status line
  echo "[setup] Using wget to fetch dataset -> raw/reviews_big.tsv"
  wget -q --show-progress https://bit.ly/battery_reviews -O raw/reviews_big.tsv

echo "[setup] Done."

