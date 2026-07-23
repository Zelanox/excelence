_HAS_SHAPER = False
_HAS_SHAPER = False

try:
    import arabic_reshaper
    print("arabic_reshaper OK")

    from bidi.algorithm import get_display
    print("python-bidi OK")

    _HAS_SHAPER = True

except Exception as e:
    print(e)

def arabic(text: str) -> str:
    """
    Reshape and reorder Arabic text for proper display in Tkinter widgets.
    If the required libraries are not available, returns the original text.
    """
    if text is None:
        return ""

    text = str(text)

    if not text or not _HAS_SHAPER:
        return text

    try:
        reshaped = arabic_reshaper.reshape(text)
        return get_display(reshaped)

    except Exception:
        return text
        
def is_available() -> bool:
    """
    Check if the required libraries for Arabic text reshaping and reordering are available.
    """
    return _HAS_SHAPER

print("Arabic shaping available:", _HAS_SHAPER)