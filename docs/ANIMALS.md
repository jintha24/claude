# Animals

Every animal in the game has a sculpted, skinned body that moves by its real gaits:
- **Horses:** Cinder, and the cab, cart and omnibus horses in London.
- **Wild animals:** red deer hinds and stags, foxes and rabbits in the hills.
- **Dogs:** the mastiff guard dogs, and the street dogs out with their owners.
- **Livestock:** sheep and cows in the village pastures.

## The bodies (`tools/animals/`)

`python3 tools/animals/build_animals.py [species ...]` writes `assets/animals/<species>.glb`.
It needs numpy, scikit-image, fast-simplification and Pillow.

- **Anatomy:** in `species.py`, each species is its skeleton's joints, taken from a side
  view in metres at the real animal's size. Over them go the shapes of the body:
  - ellipsoids for the barrel, chest, rump and muscles;
  - round cones for the leg bones, neck and face;
  - a knuckle at every joint.
  - The shapes are blended smoothly (signed distance fields, `sculpt.py`).
- **Mesh:** marching cubes, then thinned to the game's budget. The vertices are settled
  back onto the true surface, with the true normals.

  | Species | Triangles |
  |---|---|
  | Horse, cow | 16k |
  | Deer, sheep | 12k |
  | Dogs | 10k |
  | Fox | 9k |
  | Rabbit | 5k |
- **Skinning:** each vertex is shared between the shapes it lies closest to, and so
  between their bones. Joints bend smoothly.
- **Coat:** the vertex colours are masks, not colours:
  - R: the dark points (legs, mane, muzzle);
  - G: white markings (a blaze, socks, a fox's bib, a cow's patches);
  - B: the paler parts (a deer's rump patch, the belly);
  - A: ambient occlusion baked from the distance field.

  `animal.gdshader` picks the colours (`AnimalLook.COATS`), so one horse model is bay,
  dark bay, chestnut, black or grey. It adds a fine lie of hair, dappling, and mud up
  the legs.
- **Hair:** hundreds of separate locks for manes, tails, a fox's brush, a stag's
  shaggy neck and a cow's switch. They are rooted on the body's surface and hang over
  it, never through it. They are coloured by the same masks (`animal_hair.gdshader`).
- **Extras:**
  - glossy eyes;
  - a stag's antlers: a royal, with brow, bez and trez tines and a crown;
  - a cow's horns;
  - a sheep's fleece: the body shapes made lumpy with noise.

## Moving (`scripts/animals/quadruped_rig.gd`)

One rig walks them all: they share the same skeleton layout.

- **Gaits by speed**, each with its real footfall pattern:

  | Gait | Pattern |
  |---|---|
  | Walk | four beats, a lateral sequence |
  | Trot | diagonal pairs |
  | Canter | three beats |
  | Gallop | four beats and a moment in the air |
  | Bound | rabbits |

  The footfalls ease from one pattern to the next.
- **Feet:** while a foot bears weight it stays put. It moves back under the body exactly
  as fast as the body goes forward. In the air it is lifted, the knee or fetlock folding,
  and put down ahead.
- **Legs:** two-bone inverse kinematics puts the legs on their feet. Elbows bend back and
  stifles forward.
- **Body:** it rises and falls with the gait, pitches with the canter and gallop, and
  bends and leans into turns.
- **Head:** it nods with the walk and stretches out at the gallop. The ears flick, and
  prick forward when alert. The tail swishes, and streams at speed.
- **Poses:** grazing, alert, lying down, dead on its side, jumping, rearing, and sitting.

`AnimalBody` (`scripts/animals/animal_body.gd`) is the node the game uses:
- **Model and gaits:** it loads the model and sets each species' gait speeds.
- **Poses:** they ease in and out through `want(pose, value, rate)`.
- **Tack:** it adds a saddle and bridle for Cinder, and a collar, pad and bridle for
  horses in harness.
- **Update rate:** far off, it is stepped less often.

`tests/test_animals.gd` checks:
- every species builds;
- a horse walks, trots, canters and gallops by speed;
- a hoof on the ground doesn't slide (horse, deer, dog);
- the dead lie flat;
- no pose breaks a bone;
- grazing puts the head down;
- London's cab horses are real horses.
