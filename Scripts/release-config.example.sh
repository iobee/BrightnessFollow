# Copy to .env.release.local at the repository root. Keep passwords in Keychain.
export BRIGHTNESS_FOLLOW_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID1234)'
export BRIGHTNESS_FOLLOW_TEAM_ID='TEAMID1234'
export BRIGHTNESS_FOLLOW_NOTARY_PROFILE='your-notary-profile'

# Optional file-based CI keychain. Leave unset for the local login Keychain.
# export BRIGHTNESS_FOLLOW_SIGNING_KEYCHAIN=/path/to/release-signing.keychain-db
# export BRIGHTNESS_FOLLOW_NOTARY_KEYCHAIN=/path/to/release-signing.keychain-db
