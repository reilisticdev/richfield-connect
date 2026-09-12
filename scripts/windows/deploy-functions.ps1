<#
.SYNOPSIS
  Deploys the send-notification-email edge function to the live
  Richfield Connect Supabase project and sets its secrets.

.DESCRIPTION
  Secrets are passed as parameters, not hardcoded - never commit real
  values into this file. Requires the Supabase CLI (https://supabase.com/docs/guides/cli)
  installed and on PATH, and `supabase login` already run once.

.PARAMETER ResendApiKey
  Your Resend API key (starts with "re_"). Required.

.PARAMETER WebhookSecret
  The shared secret the edge function checks against the
  "x-webhook-secret" header on incoming requests. If omitted, a random
  one is generated and printed at the end - copy it into the Database
  Webhook's custom header configuration in the Supabase dashboard.

.PARAMETER FromAddress
  The "From" address/name used for outgoing emails. Must be on a domain
  verified with Resend.

.PARAMETER ProjectRef
  The Supabase project ref to link/deploy to. Defaults to the live
  richfield-connect project.

.EXAMPLE
  .\scripts\windows\deploy-functions.ps1 -ResendApiKey "re_xxx"

.EXAMPLE
  .\scripts\windows\deploy-functions.ps1 -ResendApiKey "re_xxx" -WebhookSecret "my-shared-secret" -FromAddress "Richfield Connect <notifications@richfieldconnect.co.za>"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResendApiKey,

    [string]$WebhookSecret = [guid]::NewGuid().ToString("N"),

    [string]$FromAddress = "Richfield Connect <notifications@yourverifieddomain.org>",

    [string]$ProjectRef = "omyagiwmdabalxifyoth"
)

$ErrorActionPreference = "Stop"

$supabaseCmd = Get-Command supabase -ErrorAction SilentlyContinue
if (-not $supabaseCmd) {
    Write-Error @"
Supabase CLI not found on PATH.
Install it first: https://supabase.com/docs/guides/cli/getting-started
Then run 'supabase login' once before re-running this script.
"@
    exit 1
}

Write-Host "Linking to project $ProjectRef..." -ForegroundColor Cyan
supabase link --project-ref $ProjectRef

Write-Host "Deploying send-notification-email..." -ForegroundColor Cyan
supabase functions deploy send-notification-email

Write-Host "Setting function secrets..." -ForegroundColor Cyan
supabase secrets set `
    RESEND_API_KEY=$ResendApiKey `
    WEBHOOK_SECRET=$WebhookSecret `
    NOTIFICATIONS_FROM_ADDRESS=$FromAddress

Write-Host ""
Write-Host "Done. Next steps:" -ForegroundColor Green
Write-Host "  1. In the Supabase dashboard -> Database -> Webhooks, create INSERT"
Write-Host "     triggers on 'profiles' and 'verification_audit' pointing at the"
Write-Host "     deployed function, with header:"
Write-Host "       x-webhook-secret: $WebhookSecret" -ForegroundColor Yellow
Write-Host "  2. Save that header value somewhere safe - it is not stored by this script."
