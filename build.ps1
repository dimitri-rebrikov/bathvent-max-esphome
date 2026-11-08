# Projektlokaler ESPHome-Aufruf.
#   .\build.ps1 compile ac-dimmer-test.yaml
#   .\build.ps1 run ac-dimmer-test.yaml
#   .\build.ps1 logs ac-dimmer-test.yaml
#
# Setzt alles, was sonst maschinenweit gelten wuerde, nur fuer diesen Prozess:
#   - IDF-Framework/Toolchain in .esphome\idf (2,5 GB, gitignored)
#   - ESPHome selbst aus .venv (Version in uv.lock)
#   - MSYSTEM raus, sonst verweigert ESP-IDF den Dienst in Git-Bash-Umgebungen
#   - nur das esp32-Target installieren (kein 706-MB-riscv32-Compiler)

$ErrorActionPreference = 'Stop'

$env:MSYSTEM = $null
$env:MSYSCON = $null
$env:ESPHOME_ESP_IDF_PREFIX = Join-Path $PSScriptRoot '.esphome\idf'
$env:ESPHOME_IDF_DEFAULT_TARGETS = 'esp32'

uv run esphome @args
