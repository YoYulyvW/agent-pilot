@echo off
REM AgentPilot standalone relay server (port 8861, independent from kai-fan-le-helper's 8860)
cd /d "%~dp0"
echo Starting AgentPilot relay on port 8861...
python agent_relay\relay_server.py --port 8861
pause
