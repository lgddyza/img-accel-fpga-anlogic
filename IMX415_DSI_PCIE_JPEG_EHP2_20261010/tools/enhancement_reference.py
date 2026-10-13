"""Four-direction response filter reference used by EHP2 regression."""
import cv2
import numpy as np

def line_filter(response, length):
    kernels = [np.ones((1, length), np.uint8), np.ones((length, 1), np.uint8),
               np.eye(length, dtype=np.uint8), np.fliplr(np.eye(length, dtype=np.uint8))]
    opened = [cv2.morphologyEx(response, cv2.MORPH_OPEN, kernel,
                              borderType=cv2.BORDER_REPLICATE) for kernel in kernels]
    return np.maximum.reduce(opened)
