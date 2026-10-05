// Durations.js as the sandboxes see it: the same source, run in a context.
const fs = require('fs'), vm = require('vm')
const raw = fs.readFileSync(require('path').join(__dirname, '..', 'qml', 'Durations.js'), 'utf8')
const src = raw.split('\n').filter(l => !l.trim().startsWith('.pragma')).join('\n')
const ctx = { Math, Number, String, parseFloat, isNaN }
vm.createContext(ctx)
const names = ['unitSeconds','isTime','formatSeconds','format','PRESETS','presetLabel','defaultPreset','fieldsOf','split','join']
vm.runInContext(src + ';globalThis.__D={' + names.join(',') + '}', ctx)
module.exports = ctx.__D
