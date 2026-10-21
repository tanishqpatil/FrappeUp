# First-run access

## Finding

Frappe creates the `Administrator` account during `bench new-site`. An anonymous request to the setup wizard redirects to login. After authentication, Frappe sees the incomplete setup flags and routes the Administrator into its built-in setup wizard. Our installer generated a random Administrator password but did not tell the user how to retrieve it.

## Change

1. Add `frappeup credentials --env-file PATH` on shell and PowerShell. It explicitly reveals only the initial Administrator username and password from the private workspace credentials file; it never prints the database password.
2. After a successful first installation, print the login name and the command for retrieving the password. Leave Frappe's authenticated setup redirect intact.
3. Document the login flow and validate the command and the existing site's first-login state.

## Acceptance

The CLI exposes the generated password on explicit request. `Administrator` plus that password logs into the new site, and the Frappe and ERPNext setup flags remain pending until the user completes the wizard.
