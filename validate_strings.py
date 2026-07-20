import re
import sys

def get_tokens(text):
    # Match standard string format specifiers like %@, %lld, %d, %.1f, %1$@
    return sorted(re.findall(r'%\d*\$?[a-zA-Z@]', text))

def load_strings(path):
    strings = {}
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
        # Very simple regex for Localizable.strings "key" = "value";
        matches = re.findall(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', content)
        for k, v in matches:
            strings[k] = v
    return strings

en_strings = load_strings('Resources/en.lproj/Localizable.strings')

langs = ['ja']
errors = 0

for lang in langs:
    path = f'Resources/{lang}.lproj/Localizable.strings'
    lang_strings = load_strings(path)
    
    for key, en_val in en_strings.items():
        if key not in lang_strings:
            print(f"[{lang}] Missing key: {key}")
            errors += 1
            continue
            
        lang_val = lang_strings[key]
        en_tokens = get_tokens(en_val)
        lang_tokens = get_tokens(lang_val)
        
        # In localized strings, format specifiers might be reordered like %1$@, %2$@ 
        # But let's at least check if the base types and counts are roughly the same
        # Actually, let's just extract the raw types ignoring position index for basic validation
        en_types = sorted([re.sub(r'\d+\$', '', t) for t in en_tokens])
        lang_types = sorted([re.sub(r'\d+\$', '', t) for t in lang_tokens])
        
        if en_types != lang_types:
            print(f"[{lang}] Token mismatch for key '{key}':")
            print(f"  EN: {en_val} -> {en_types}")
            print(f"  {lang}: {lang_val} -> {lang_types}")
            errors += 1

if errors == 0:
    print("All string interpolation tokens match perfectly!")
else:
    print(f"Found {errors} errors.")
