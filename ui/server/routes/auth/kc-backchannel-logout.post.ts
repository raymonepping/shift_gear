// Keycloak backchannel logout receiver.
// Keycloak POSTs a signed logout token here when a user's SSO session ends.
// Our session is already destroyed before we redirect to Keycloak's end-session
// endpoint (logout.post.ts), so we only need to acknowledge receipt.
// Registering this URL on the vault client tells Keycloak to do the server-to-
// server call and then redirect immediately to post_logout_redirect_uri without
// showing the "Do you want to log out?" browser confirmation page.
export default defineEventHandler(() => {
  // Acknowledge; Keycloak expects 200 with no content.
  return null
})
