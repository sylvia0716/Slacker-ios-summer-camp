// Resolve names from trusted Firebase Auth records, never client-supplied identities.
function memberDisplayName(user) {
  const nickname = user.displayName?.trim();
  if (nickname) return nickname.slice(0, 60);
  const email = user.email?.trim();
  if (email) return email;
  return `成員 ${user.uid.slice(0, 8)}`;
}

module.exports = {memberDisplayName};
