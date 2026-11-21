/**
 * Expected, user-safe search failure, such as an unknown or inactive configuration.
 * Messages always come from Custom Labels, so the controller can pass them to site visitors.
 * Unexpected errors use other exception types and are replaced with a generic message.
 */
public inherited sharing class SiteSearchException extends Exception {
}
