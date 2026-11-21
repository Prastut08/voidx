with open(r'C:\Users\Aryan\OneDrive\Documents\Desktop\ASTRA\sahaya\apps\mobile\build\web\main.dart.js', 'r', encoding='utf-8') as f:
    text = f.read()

import re
tags = set(re.findall(r'createElement\([\'"](flt-[a-z-]+)[\'"]\)', text))
print('Flutter created tags:', tags)

glass = set(re.findall(r'[a-zA-Z0-9_\.]*glass[a-zA-Z0-9_\.]*', text, re.IGNORECASE))
print('Glass matches:', list(glass)[:10])
