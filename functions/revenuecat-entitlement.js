// The RevenueCat App User ID is always the authenticated Firebase UID.
// Never accept an entitlement or user ID supplied by the app.
async function proStatusForUser(userID, options = {}) {
  const key = options.key ?? process.env.REVENUECAT_PUBLIC_API_KEY;
  if (!key) return 'inactive';
  try {
    const response = await (options.fetchImpl ?? fetch)(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userID)}`, {
      headers: {Authorization: `Bearer ${key}`},
      signal: AbortSignal.timeout(5000),
    });
    if (response.status === 404) return 'inactive';
    if (!response.ok) return 'unknown';
    const data = await response.json();
    const entitlement = data.subscriber?.entitlements?.oops_bomb_pro;
    if (!entitlement) return 'inactive';
    if (entitlement.expires_date == null) return 'active';
    const expiry = Math.max(
        Date.parse(entitlement.expires_date) || 0,
        Date.parse(entitlement.grace_period_expires_date) || 0);
    return expiry > (options.now ?? Date.now()) ? 'active' : 'inactive';
  } catch {
    return 'unknown';
  }
}

module.exports = {proStatusForUser};
