#!/usr/bin/env python3
"""Mean absolute pixel difference between two screenshots of the Mac VM (0 identical .. 255): python3 pixdiff.py real.png ours.png   (needs pillow, numpy: ~/.pear/venv)
Prints the whole screen, the Dock strip (bottom 80 rows) and the rest."""
import sys
from PIL import Image
import numpy as np
a=Image.open(sys.argv[1]).convert('RGB'); b=Image.open(sys.argv[2]).convert('RGB')
A=np.array(a).astype(int); B=np.array(b).astype(int); h=A.shape[0]
print('whole %.2f   dock strip %.2f   rest %.2f' % (np.abs(A-B).mean(), np.abs(A[h-80:]-B[h-80:]).mean(), np.abs(A[:h-80]-B[:h-80]).mean()))
