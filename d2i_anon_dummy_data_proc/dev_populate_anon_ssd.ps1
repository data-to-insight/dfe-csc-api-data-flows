# 140125

# Connection Details
$server = "ESLLREPORTS04V"
$database = "HDM_Local"
$connectionString = "Server=$server;Database=$database;Trusted_Connection=True;"

# Dummy table prefix
$dummyPrefix = "ssd_dummy_"

# Anonymization settings
$randomNames = @("John Doe", "Jane Smith", "Alex Johnson", "Chris Brown")
$randomWords = @("Alpha", "Beta", "Gamma", "Delta")
$dateShift = 365 # Days to shift dates +/- randomly

function Get-DatabaseData {
    param (
        [string]$query
    )
    $connection = New-Object System.Data.SqlClient.SqlConnection $connectionString
    $command = $connection.CreateCommand()
    $command.CommandText = $query
    $connection.Open()

    $reader = $command.ExecuteReader()
    $results = @()
    while ($reader.Read()) {
        $row = @{}
        for ($i = 0; $i -lt $reader.FieldCount; $i++) {
            $row[$reader.GetName($i)] = $reader.GetValue($i)
        }
        $results += $row
    }
    $connection.Close()
    return $results
}

function AnonymizeData {
    param (
        [hashtable]$row
    )
    $anonymizedRow = @{}
    foreach ($key in $row.Keys) {
        $value = $row[$key]
        if ($value -is [string]) {
            if ($key -like "*name*" -or $key -like "*label*") {
                $anonymizedRow[$key] = $randomNames | Get-Random
            } else {
                $anonymizedRow[$key] = $randomWords | Get-Random
            }
        } elseif ($value -is [datetime]) {
            $shift = Get-Random -Minimum -$dateShift -Maximum $dateShift
            $anonymizedRow[$key] = $value.AddDays($shift)
        } elseif ($value -is [int] -or $value -is [double]) {
            $anonymizedRow[$key] = $value # Keep numeric values as is or apply noise
        } else {
            $anonymizedRow[$key] = $null
        }
    }
    return $anonymizedRow
}

function GenerateInsertStatements {
    param (
        [string]$tableName,
        [array]$data
    )
    $statements = @()
    foreach ($row in $data) {
        $columns = $row.Keys -join ", "
        $values = $row.Values | ForEach-Object {
            if ($_ -is [string]) { "'$_'" }
            elseif ($_ -is [datetime]) { "'$($_.ToString("yyyy-MM-dd"))'" }
            elseif ($_ -eq $null) { "NULL" }
            else { $_ }
        } -join ", "
        $statements += "INSERT INTO $dummyPrefix$tableName ($columns) VALUES ($values);"
    }
    return $statements
}

# Main Script
$tables = @("ssd_person", "ssd_linked_identifiers", "ssd_cin_episodes", "ssd_involvements", "ssd_professionals")

foreach ($table in $tables) {
    Write-Host "Processing table: $table"

    # Fetch data
    $query = "SELECT TOP 10 * FROM $table" # Limit to 10 rows for testing
    $data = Get-DatabaseData -query $query

    # Anonymize data
    $anonymizedData = $data | ForEach-Object { AnonymizeData -row $_ }

    # Generate INSERT statements
    $insertStatements = GenerateInsertStatements -tableName $table -data $anonymizedData

    # Write to file
    $outputFile = "$dummyPrefix$table.sql"
    $insertStatements -join "`n" | Out-File -FilePath $outputFile -Encoding UTF8

    Write-Host "Anonymized data written to $outputFile"
}