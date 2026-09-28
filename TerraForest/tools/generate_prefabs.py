"""Generate original editable example block assets; never runs in the game loop."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / 'addons/structures/prefabs'


def save(name, title, cells):
    records = [value for position, word in sorted(cells.items()) for value in (*position, word)]
    text = '[gd_resource type="NativeBlockPrefab" format=3]\n\n[resource]\n'
    text += 'resource_name = ' + json.dumps(title) + '\n'
    text += 'records = PackedInt32Array(' + ', '.join(map(str, records)) + ')\n'
    (DESTINATION / (name + '.tres')).write_text(text, encoding='utf-8')
    print(f'{name}: {len(cells)} cells')


def main():
    DESTINATION.mkdir(parents=True, exist_ok=True)
    cabin = {}
    for z in range(-5, 6):
        for x in range(-4, 5):
            cabin[x, -1, z] = 65  # Concrete foundation, below the floor.
            cabin[x, 0, z] = 33   # Timber floor.
            for y in range(1, 5):
                perimeter = abs(x) == 4 or abs(z) == 5
                door = z == 5 and x == 0 and y <= 2
                window = y in (2, 3) and (
                    (abs(z) == 5 and abs(x) == 2) or
                    (abs(x) == 4 and abs(z) in (1, 2)))
                if perimeter and not door and not window:
                    cabin[x, y, z] = 1
    for z in range(-6, 7):
        for x in range(-4, 5):
            roof_y = 9 - abs(x)
            cabin[x, roof_y, z] = 34 if x == 0 else 36 + ((3 if x < 0 else 1) << 3)
            if abs(z) == 5:
                for y in range(5, roof_y):
                    cabin[x, y, z] = 1
    for x in range(-1, 2):
        cabin[x, 0, 6] = 3 + (2 << 3) + 64
    save('brick_cottage', 'Brick cottage', cabin)

    staircase = {}
    for z in range(4):
        for x in range(-1, 2):
            for y in range(z):
                staircase[x, y, z] = 65
            staircase[x, z, z] = 67
        for x in (-2, 2):
            staircase[x, z, z] = 101
            staircase[x, z + 1, z] = 101
    save('stair_flight', 'Four-metre stair flight', staircase)

    wall = {}
    for x in range(-3, 4):
        for y in range(5):
            if x != 0 or y >= 3:
                wall[x, y, 0] = 65 if y == 4 else 1
    save('doorway_wall', 'Doorway wall', wall)

    tower = {}
    for z in range(-8, 9):
        for x in range(-8, 9):
            shaft = -1 <= x <= 1 and 0 <= z <= 3
            if not shaft:
                tower[x, 0, z] = 65
            perimeter = abs(x) == 8 or abs(z) == 8
            pillar = perimeter and x % 4 == 0 and z % 4 == 0
            entrance = z == 8 and abs(x) <= 1
            if perimeter and not entrance:
                tower[x, 1, z] = 65
            if pillar and not entrance:
                for y in range(1, 4):
                    tower[x, y, z] = 97
    # Open shaft and four-metre stair rise connect storeys at Y increments of 4.
    for z in range(4):
        for x in range(-1, 2):
            for y in range(1, z + 1):
                tower[x, y, z] = 65
            tower[x, z + 1, z] = 67
    save('tower_floor', 'Tower floor', tower)


if __name__ == '__main__':
    main()
