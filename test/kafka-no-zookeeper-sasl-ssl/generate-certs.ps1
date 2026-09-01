<#
.SYNOPSIS
Generates a local CA plus a broker keystore/truststore (PKCS12 format) for
the SASL_SSL example. Re-run any time to regenerate fresh certs.

PKCS12 is used (instead of PEM) because the apache/kafka Docker image's
configure script requires a keystore filename + credentials-file pair
(KAFKA_SSL_KEYSTORE_FILENAME / KAFKA_SSL_KEYSTORE_CREDENTIALS /
KAFKA_SSL_KEY_CREDENTIALS). Requires openssl and docker (docker is used to
run keytool from the apache/kafka image itself, so no host JDK is needed).

Set $env:CERT_PASSWORD before running to override the default store password.
#>
$ErrorActionPreference = "Stop"

function Invoke-Checked {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList
    )
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath $($ArgumentList -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Write-TextFile {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content)
}

$Days = 3650
$Password = if ($env:CERT_PASSWORD) { $env:CERT_PASSWORD } else { "changeit" }
$OutDir = Join-Path $PSScriptRoot "secrets"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Set-Location $OutDir
# Set-Location updates PowerShell's own location (which child processes like
# openssl correctly inherit), but .NET APIs such as [System.IO.File] resolve
# relative paths against Environment.CurrentDirectory, which doesn't follow
# Set-Location automatically. Keep them in sync so Write-TextFile below works.
[Environment]::CurrentDirectory = $OutDir

Write-Host "Generating CA..."
Invoke-Checked openssl @('genrsa', '-out', 'ca.key', '4096')
Invoke-Checked openssl @('req', '-x509', '-new', '-nodes', '-key', 'ca.key', '-sha256', '-days', "$Days", '-subj', '/CN=kafka-example-ca', '-out', 'ca.crt')

Write-Host "Generating broker key + CSR..."
Invoke-Checked openssl @('genrsa', '-out', 'kafka.key', '2048')
Invoke-Checked openssl @('req', '-new', '-key', 'kafka.key', '-subj', '/CN=kafka', '-out', 'kafka.csr')

Write-TextFile -Path 'kafka.ext' -Content "subjectAltName = DNS:kafka,DNS:localhost,IP:127.0.0.1`nextendedKeyUsage = serverAuth,clientAuth`n"

Write-Host "Signing broker certificate with CA..."
Invoke-Checked openssl @('x509', '-req', '-in', 'kafka.csr', '-CA', 'ca.crt', '-CAkey', 'ca.key', '-CAcreateserial', '-out', 'kafka.crt', '-days', "$Days", '-sha256', '-extfile', 'kafka.ext')

Write-Host "Building PKCS12 keystore (broker key + cert + CA chain)..."
Invoke-Checked openssl @('pkcs12', '-export', '-in', 'kafka.crt', '-inkey', 'kafka.key', '-certfile', 'ca.crt', '-name', 'kafka', '-out', 'kafka.keystore.p12', '-passout', "pass:$Password")

Write-Host "Building PKCS12 truststore (CA cert only)..."
# openssl's "pkcs12 -export -nokeys" produces a certificate bag that Java's
# PKCS12 provider doesn't load as a trusted entry, so use keytool (via the
# broker image itself) to build the truststore instead.
Remove-Item -Force -ErrorAction SilentlyContinue 'kafka.truststore.p12'
Invoke-Checked docker @('run', '--rm', '-v', "${OutDir}:/certs", '--entrypoint', 'keytool', 'apache/kafka:latest', '-importcert', '-noprompt', '-alias', 'kafka-example-ca', '-file', '/certs/ca.crt', '-keystore', '/certs/kafka.truststore.p12', '-storetype', 'PKCS12', '-storepass', $Password)

# Credential files read by the apache/kafka image's configure script.
# PKCS12 requires the key password to match the keystore password.
Write-TextFile -Path 'kafka_keystore_creds' -Content $Password
Write-TextFile -Path 'kafka_key_creds' -Content $Password
Write-TextFile -Path 'kafka_truststore_creds' -Content $Password

Remove-Item -Force -ErrorAction SilentlyContinue 'kafka.csr', 'kafka.ext', 'ca.srl'

Write-Host "Done. Certs written to $OutDir (password: $Password)"
