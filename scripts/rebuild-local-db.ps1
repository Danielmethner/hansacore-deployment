
# This script rebuilds the hansacore database schema on the local cluster and restarts the API pod to trigger demo data seeding.

Write-Host "Finding postgres pod..."
$postgresPod = kubectl get pods -n hansacore -l app=postgres -o jsonpath="{.items[0].metadata.name}"

if (-not $postgresPod) {
    Write-Error "Postgres pod not found in namespace hansacore."
    exit 1
}

Write-Host "Postgres pod found: $postgresPod"
Write-Host "Rebuilding hansacore schema..."

$sqlCommand = "DROP SCHEMA IF EXISTS hansacore CASCADE; CREATE SCHEMA hansacore AUTHORIZATION hansacore_api;"
kubectl exec -it $postgresPod -n hansacore -- psql -U postgres -d hansacore -c $sqlCommand

Write-Host "Schema rebuilt. Restarting hansacore-api pod..."
kubectl rollout restart deployment/hansacore-api -n hansacore
kubectl rollout status deployment/hansacore-api -n hansacore

Write-Host "Database rebuild and pod restart complete."

