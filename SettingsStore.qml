import QtQuick

// Saves one on/off setting of the widget. `owner` is the bar panel: it holds
// `settings`, `moduleName` and `bar`.
//
// The value is applied to the owner first so the screen redraws on the click
// itself. The shell.json write comes back through the bar as the same value,
// and nothing is written when the shell offers no write call.
QtObject {
  property var owner: null

  function toggle(key, fallback) {
    if (!owner) return
    var current = owner.settings ? owner.settings[key] : undefined
    var value = current === undefined || current === null ? fallback : current === true || current === "true"
    var entry = { id: owner.moduleName }
    for (var name in owner.settings) if (name !== "id") entry[name] = owner.settings[name]
    entry[key] = !value
    owner.settings = entry
    if (owner.bar && owner.bar.shell && typeof owner.bar.shell.updateEntryInline === "function")
      owner.bar.shell.updateEntryInline(owner.moduleName, entry)
  }
}
