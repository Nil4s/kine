"""L16: which licence covers a shipped DLL. One table, used by make_notices.py (writes it) and check_notices.py (checks it).
A DLL that matches no rule is UNKNOWN: the build must stop until someone writes down its licence."""
import re

RULES = [
    (r"^kine_(native|cad)\.windows\.template_release\.x86_64\.dll$", "Kine (own code) with godot-cpp, MIT (licences/godot-cpp-MIT.txt)"),
    (r"^libTK[A-Za-z0-9_]*\.dll$", "Open CASCADE Technology 8.0.1, LGPL-2.1 with the Open CASCADE Exception 1.0 (licences/LGPL-2.1.txt, OCCT_LGPL_EXCEPTION.txt)"),
    (r"^(libstdc\+\+-6|libgcc_s_seh-1)\.dll$", "GCC runtime, GPL-3.0 with the GCC Runtime Library Exception"),
    (r"^libwinpthread-1\.dll$", "winpthreads, MIT-style"),
]


def licence(name):
    for rx, text in RULES:
        if re.match(rx, name, re.I):
            return text
    return None
