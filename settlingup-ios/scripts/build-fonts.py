"""Generate static Outfit faces from the bundled variable font (FontTools 4.60.2)."""
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

folder = Path(__file__).resolve().parents[1] / 'SettlingUpApp' / 'Fonts'
for weight, style in [(400, 'Regular'), (600, 'SemiBold'), (700, 'Bold'), (800, 'ExtraBold')]:
    font = instantiateVariableFont(TTFont(folder / 'Outfit.ttf'), {'wght': weight}, updateFontNames=True)
    name = font['name'].getDebugName(6)
    output = folder / f'Outfit-{style}.ttf'
    font.save(output)
    print(f'{output.name}: {name}')
