_HAS_SHAPER = False
try:
    import arabic_reshaper
    from bidi.algorithm import get_display
    _HAS_SHAPER = True
except ImportError:
    pass

def ar(text: str) -> str:
    """
    Reshape and reorder Arabic text for proper display in Tkinter widgets.
    If the required libraries are not available, returns the original text.
    """
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