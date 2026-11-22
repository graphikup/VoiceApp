/// Picto Voix : à chaque démarrage, s'assure que le compte famille existe
/// et que les sauvegardes et la protection anti-essais de mot de passe sont actives.
onBootstrap((e) => {
  e.next();
  const email = $os.getenv("PV_FAMILY_EMAIL");
  const password = $os.getenv("PV_FAMILY_PASSWORD");
  if (email && password) {
    let exists = true;
    try { e.app.findAuthRecordByEmail("users", email); } catch (err) { exists = false; }
    if (!exists) {
      const rec = new Record(e.app.findCollectionByNameOrId("users"));
      rec.setEmail(email);
      rec.setPassword(password);
      rec.setVerified(true);
      rec.set("name", "Famille");
      e.app.save(rec);
      console.log("Picto Voix : compte famille créé pour " + email);
    }
  }
  const s = e.app.settings();
  let changed = false;
  if (!s.backups.cron) { s.backups.cron = "30 3 * * *"; s.backups.cronMaxKeep = 14; changed = true; }
  if (!s.rateLimits.enabled) { s.rateLimits.enabled = true; changed = true; }
  if (s.meta.appName !== "Picto Voix") { s.meta.appName = "Picto Voix"; changed = true; }
  if (changed) e.app.save(s);
});
