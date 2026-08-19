"""Crude structural check on the QML files -- no Qt here, so this catches
unbalanced braces/parens/brackets, unterminated strings, duplicate ids within
a file, and references to id names that are never declared."""
import re, sys, glob, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BAD = 0
def bad(msg):
    global BAD
    BAD += 1
    print("FAIL " + msg)

files = sorted(glob.glob(os.path.join(ROOT, 'qml', '**', '*.qml'), recursive=True))
for path in files:
    src = open(path, encoding='utf-8').read()
    rel = os.path.relpath(path, ROOT)

    # Strip STRINGS FIRST, then comments. The other order eats the //theme
    # part of "image://theme/..." and reports a false unterminated string.
    s = re.sub(r'"(?:[^"\\\n]|\\.)*"', '"S"', src)
    s = re.sub(r"'(?:[^'\\\n]|\\.)*'", "'S'", s)
    s = re.sub(r'//[^\n]*', '', s)
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.S)
    stripped = s

    if stripped.count('"') % 2 or stripped.count("'") % 2:
        bad(f"{rel}: unterminated string literal")

    for open_c, close_c, name in (('{','}','brace'), ('(',')','paren'), ('[',']','bracket')):
        d = stripped.count(open_c) - stripped.count(close_c)
        if d:
            bad(f"{rel}: unbalanced {name}s ({d:+d})")

    # Anchor to end of line: `id: page.habitId,` inside a JS object is a
    # property called id, not a QML id, and the old pattern flagged it.
    ids = re.findall(r'^\s*id:\s*([A-Za-z_]\w*)\s*$', s, flags=re.M)
    dupes = {i for i in ids if ids.count(i) > 1}
    if dupes:
        bad(f"{rel}: duplicate ids {sorted(dupes)}")

    print(f"ok   {rel}  ({len(src.splitlines())} lines, {len(ids)} ids)")

# every file listed in DISTFILES must exist, and every qml file must be listed
pro = open(os.path.join(ROOT, 'harbour-fiatmos.pro'), encoding='utf-8').read()
listed = set(re.findall(r'(qml/[\w/.-]+|rpm/[\w/.-]+)', pro))
for f in listed:
    if not os.path.exists(os.path.join(ROOT, f)):
        bad(f"DISTFILES lists {f} but it does not exist")
for path in files + [os.path.join(ROOT, 'qml', 'Storage.js'), os.path.join(ROOT, 'qml', 'qmldir')]:
    rel = os.path.relpath(path, ROOT)
    if rel not in listed:
        bad(f"{rel} exists but is not in DISTFILES -- it will not deploy")
if BAD:
    # Loud on failure, and never an empty last line. This printed "" when
    # something was wrong, so `qmlcheck.py | tail -1` showed nothing at all
    # and read exactly like success. A check that fails quietly is worse than
    # no check, because it is trusted.
    print(f"\nFAILED -- {BAD} problem(s) above. Do not build.")
    sys.exit(1)

print("ok   DISTFILES matches the tree")
print("\nPASSED -- every QML file parses and DISTFILES matches the tree.")
sys.exit(0)
