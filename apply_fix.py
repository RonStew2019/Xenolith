"""Revert feet back to Z=0."""

with open("generate_character.py", "r", encoding="utf-8") as f:
    src = f.read()

src = src.replace(
    '"FootL":     ("ShinL",   (0, -0.33, -0.07), (-0.12, 0.06, -0.07)),',
    '"FootL":     ("ShinL",   (0, -0.33, 0),     (-0.12, 0.06, 0)),'
)
src = src.replace(
    '"FootR":     ("ShinR",   (0, -0.33, -0.07), (0.12, 0.06, -0.07)),',
    '"FootR":     ("ShinR",   (0, -0.33, 0),     (0.12, 0.06, 0)),'
)
src = src.replace(
    '("ellipsoid", (-0.12, 0.06, -0.07), (0.09, 0.09, 0.09),  "FootL"),',
    '("ellipsoid", (-0.12, 0.06, 0),   (0.09, 0.09, 0.09),    "FootL"),'
)
src = src.replace(
    '("ellipsoid", (0.12, 0.06, -0.07),  (0.09, 0.09, 0.09),  "FootR"),',
    '("ellipsoid", (0.12, 0.06, 0),    (0.09, 0.09, 0.09),    "FootR"),'
)

with open("generate_character.py", "w", encoding="utf-8") as f:
    f.write(src)
print("Feet reverted to Z=0.")
