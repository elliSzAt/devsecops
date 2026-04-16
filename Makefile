.PHONY: all pipeline build test scan policy dashboard clean

# Run full DevSecOps pipeline
all: pipeline

# Full pipeline (build → test → security scans → policy gate)
pipeline:
	docker compose up pipeline-runner --build --abort-on-container-exit

# Build application only
build:
	docker compose build app

# Run individual security scans
sast:
	docker compose up sast-scan --build --abort-on-container-exit

sca:
	docker compose up sca-scan --build --abort-on-container-exit

container-scan:
	docker compose up container-scan --build --abort-on-container-exit

iac-scan:
	docker compose up iac-scan --build --abort-on-container-exit

# Run all scans in parallel
scan:
	docker compose up sast-scan sca-scan container-scan iac-scan --build

# Policy enforcement
policy:
	docker compose up policy-check --build --abort-on-container-exit

# Start security dashboard
dashboard:
	docker compose up dashboard -d
	@echo "Dashboard available at http://localhost:8080"

# Start the app
app:
	docker compose up app --build -d
	@echo "App running at http://localhost:3000"

# Pipeline security audit
pipeline-security:
	docker compose run --rm pipeline-runner bash /workspace/pipeline/scripts/pipeline-security-check.sh

# Clean up
clean:
	docker compose down -v --remove-orphans
	rm -f reports/*.json

# View reports
reports:
	@echo "=== SAST Report ===" && cat reports/sast-report.json | python3 -m json.tool 2>/dev/null || echo "No SAST report"
	@echo "=== Policy Report ===" && cat reports/policy-report.json | python3 -m json.tool 2>/dev/null || echo "No policy report"
