@echo off
REM AgentPilot AI bot bridge: phone App <-> relay <-> local AI CLI (like feishu bot)
REM Edit the --ai line to match your local AI CLI.
REM   codex:  --ai "codex exec {message}"
REM   claude: --ai "claude -p {message}"
cd /d "%~dp0"
set NO_PROXY=192.168.2.250,127.0.0.1,localhost
python ai_bot.py --relay http://192.168.2.250:8861 --name WorkBuddy --ai "codex exec {message}"
pause
