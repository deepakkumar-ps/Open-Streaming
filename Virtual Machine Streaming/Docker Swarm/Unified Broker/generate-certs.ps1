<#
.SYNOPSIS
Generates every certificate/keystore the multi-listener secured Kafka stack
needs, plus client material for the Bridge / VPS / Gateway services.

  ca.crt / ca.key         local CA. ca.crt is what clients trust.
  kafka.keystore.p12      broker identity (shared by all TLS listeners)
  kafka.truststore.p12    CA, used to validate client certs (mTLS listeners)
  kafka_*_creds           password files
  client.crt / client.key PEM client cert for librdkafka clients
  kafka-ui.keystore.p12   PKCS12 client cert for kafka-ui (Java)
  kafka_server_jaas.conf  copied in from the repo (broker SCRAM JAAS entry)

Requires openssl and docker (docker runs keytool from the apache/kafka image,
so no host JDK is needed). Safe to re-run.

The broker SAN must cover EVERY hostname/IP a TLS client uses to reach Kafka,
or hostname verification fails.

  $env:CERT_PASSWORD = "..."     override store password (default: changeit)
  $env:KAFKA_NODE_IP = "..."     override Kafka node IP (default: 10.104.10.89)
  $env:EXTRA_SANS    = "DNS:kafka.internal,IP:10.104.10.90"

.NOTES
If this machine also has Strawberry Perl installed, PowerShell resolves ITS
openssl.exe before Git's, and that build looks for a config file at a path that
does not exist locally — the first openssl command then fails with
"Can't open .../openssl.cnf for reading". Check with:  Get-Command openssl -All
Fix by setting, in the same session:
  $env:OPENSSL_CONF = "C:\Program Files\Git\mingw64\etc\ssl\openssl.cnf"
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

$Days        = 3650
$Password    = if ($env:CERT_PASSWORD) { $env:CERT_PASSWORD } else { "changeit" }
$KafkaNodeIp = if ($env:KAFKA_NODE_IP)  { $env:KAFKA_NODE_IP }  else { "10.104.10.89" }
$BaseSans    = "DNS:kafka,DNS:localhost,IP:127.0.0.1,IP:$KafkaNodeIp"
$Sans        = if ($env:EXTRA_SANS) { "$BaseSans,$($env:EXTRA_SANS)" } else { $BaseSans }

$OutDir = Join-Path $PSScriptRoot "secrets"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Set-Location $OutDir
# Set-Location updates PowerShell's location (inherited by child processes like
# openssl), but .NET APIs such as [System.IO.File] resolve relative paths against
# Environment.CurrentDirectory, which does NOT follow Set-Location. Keep in sync.
[Environment]::CurrentDirectory = $OutDir

Write-Host "Broker certificate SAN: $Sans"
Write-Host ""

Write-Host "[1/5] Generating CA..."
Invoke-Checked openssl @('genrsa', '-out', 'ca.key', '4096')
Invoke-Checked openssl @('req', '-x509', '-new', '-nodes', '-key', 'ca.key', '-sha256',
                         '-days', "$Days", '-subj', '/CN=kafka-security-test-ca', '-out', 'ca.crt')

Write-Host "[2/5] Generating broker certificate..."
Invoke-Checked openssl @('genrsa', '-out', 'kafka.key', '2048')
Invoke-Checked openssl @('req', '-new', '-key', 'kafka.key', '-subj', '/CN=kafka', '-out', 'kafka.csr')
Write-TextFile -Path 'kafka.ext' -Content "subjectAltName = $Sans`nextendedKeyUsage = serverAuth,clientAuth`n"
Invoke-Checked openssl @('x509', '-req', '-in', 'kafka.csr', '-CA', 'ca.crt', '-CAkey', 'ca.key',
                         '-CAcreateserial', '-out', 'kafka.crt', '-days', "$Days", '-sha256',
                         '-extfile', 'kafka.ext')

Write-Host "[3/5] Building broker PKCS12 keystore..."
Invoke-Checked openssl @('pkcs12', '-export', '-in', 'kafka.crt', '-inkey', 'kafka.key',
                         '-certfile', 'ca.crt', '-name', 'kafka', '-out', 'kafka.keystore.p12',
                         '-passout', "pass:$Password")

Write-Host "[4/5] Building PKCS12 truststore (CA only)..."
# openssl's "pkcs12 -export -nokeys" produces a certificate bag that Java's
# PKCS12 provider will not load as a *trusted* entry, so use keytool instead.
Remove-Item -Force -ErrorAction SilentlyContinue 'kafka.truststore.p12'
Invoke-Checked docker @('run', '--rm', '-v', "${OutDir}:/certs", '--entrypoint', 'keytool',
                        'apache/kafka:latest', '-importcert', '-noprompt',
                        '-alias', 'kafka-security-test-ca', '-file', '/certs/ca.crt',
                        '-keystore', '/certs/kafka.truststore.p12',
                        '-storetype', 'PKCS12', '-storepass', $Password)

function New-ClientCert {
    param([Parameter(Mandatory)][string]$Name)
    Write-Host "      client certificate: $Name"
    Invoke-Checked openssl @('genrsa', '-out', "$Name.key", '2048')
    Invoke-Checked openssl @('req', '-new', '-key', "$Name.key", '-subj', "/CN=$Name", '-out', "$Name.csr")
    Write-TextFile -Path "$Name.ext" -Content "extendedKeyUsage = clientAuth`n"
    Invoke-Checked openssl @('x509', '-req', '-in', "$Name.csr", '-CA', 'ca.crt', '-CAkey', 'ca.key',
                             '-CAcreateserial', '-out', "$Name.crt", '-days', "$Days", '-sha256',
                             '-extfile', "$Name.ext")
    Remove-Item -Force -ErrorAction SilentlyContinue "$Name.csr", "$Name.ext"
}

Write-Host "[5/5] Generating client certificates..."
# PEM pair for librdkafka clients (Bridge Service, VPS, Gateway)
New-ClientCert -Name 'client'
# PKCS12 for kafka-ui (Java client)
New-ClientCert -Name 'kafka-ui'
Invoke-Checked openssl @('pkcs12', '-export', '-in', 'kafka-ui.crt', '-inkey', 'kafka-ui.key',
                         '-certfile', 'ca.crt', '-name', 'kafka-ui', '-out', 'kafka-ui.keystore.p12',
                         '-passout', "pass:$Password")

Write-TextFile -Path 'kafka_keystore_creds'   -Content $Password
Write-TextFile -Path 'kafka_key_creds'        -Content $Password
Write-TextFile -Path 'kafka_truststore_creds' -Content $Password

# Broker JAAS entry is version-controlled (holds no secrets) but must sit
# alongside the certs, so deployment is a single "scp -r secrets".
Copy-Item -Force (Join-Path $PSScriptRoot 'kafka_server_jaas.conf') (Join-Path $OutDir 'kafka_server_jaas.conf')

Remove-Item -Force -ErrorAction SilentlyContinue 'kafka.csr', 'kafka.ext', 'ca.srl'

Write-Host ""
Write-Host "Done. Written to $OutDir (store password: $Password)"
Write-Host ""
Write-Host "Verify the SAN took effect:"
Write-Host "  openssl x509 -in secrets/kafka.crt -noout -text | Select-String -Context 0,1 'Subject Alternative Name'"
