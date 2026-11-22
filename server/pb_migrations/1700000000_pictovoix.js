/// Picto Voix : structure des données synchronisées (une famille = un compte)
migrate((app) => {
  const users = app.findCollectionByNameOrId("users");
  // session valable un an : on ne redemande pas le mot de passe sur la tablette de l'enfant
  users.authToken.duration = 31536000;
  // pas d'inscription libre : les comptes sont créés par l'administrateur
  users.createRule = null;
  app.save(users);

  const own = "owner = @request.auth.id";
  const records = new Collection({
    type: "base",
    name: "pv_records",
    listRule: own, viewRule: own, deleteRule: own,
    createRule: "@request.auth.id != '' && owner = @request.auth.id",
    updateRule: own + " && (@request.body.owner:isset = false || @request.body.owner = @request.auth.id)",
    fields: [
      { name: "owner", type: "relation", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { name: "kind", type: "text", required: true, max: 20 },
      { name: "uid", type: "text", required: true, max: 64 },
      { name: "data", type: "json", maxSize: 2000000 },
      { name: "updatedAt", type: "number" },
      { name: "deleted", type: "bool" },
      { name: "created", type: "autodate", onCreate: true, onUpdate: false },
      { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
    ],
    indexes: [
      "CREATE UNIQUE INDEX idx_pv_records_uid ON pv_records (owner, kind, uid)",
      "CREATE INDEX idx_pv_records_updated ON pv_records (owner, updated)",
    ],
  });
  app.save(records);

  const images = new Collection({
    type: "base",
    name: "pv_images",
    listRule: own, viewRule: own, deleteRule: own,
    createRule: "@request.auth.id != '' && owner = @request.auth.id",
    updateRule: own + " && (@request.body.owner:isset = false || @request.body.owner = @request.auth.id)",
    fields: [
      { name: "owner", type: "relation", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { name: "uid", type: "text", required: true, max: 64 },
      // fichiers protégés : visibles seulement avec un jeton du compte
      { name: "file", type: "file", required: true, maxSelect: 1, maxSize: 8388608, protected: true,
        mimeTypes: ["image/jpeg", "image/png", "image/webp", "image/svg+xml", "image/gif"] },
      { name: "source", type: "text", max: 20 },
      { name: "ref", type: "text", max: 64 },
      { name: "updatedAt", type: "number" },
      { name: "deleted", type: "bool" },
      { name: "created", type: "autodate", onCreate: true, onUpdate: false },
      { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
    ],
    indexes: [
      "CREATE UNIQUE INDEX idx_pv_images_uid ON pv_images (owner, uid)",
      "CREATE INDEX idx_pv_images_updated ON pv_images (owner, updated)",
    ],
  });
  app.save(images);
}, (app) => {
  for (const n of ["pv_images", "pv_records"]) {
    try { app.delete(app.findCollectionByNameOrId(n)); } catch (e) {}
  }
});
