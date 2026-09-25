# Greater London and the bigger hills

The world used to be one neighbourhood (about 174 m × 147 m) and 2 km × 2 km of hills.
Now it is:

| Place | Size | What's there |
|---|---|---|
| **London** | 3.4 km × 3.4 km = **11.6 km²** | The old streets in the middle, and round them about 1,240 city blocks and 46,000 houses, shops, pubs and warehouses. Also the Thames with four bridges, St Paul's, Westminster, garden squares, parish churches, parks, passers-by, street sellers and constables. |
| **The hills** | 4.1 km × 4.1 km = **16.8 km²** | Harry's cave, the lake and the woods as before, plus four villages (Highgate, Kentish Green, Northwold, Westcombe) with cottages, a church, an inn, a smithy, barns and villagers. Also farms of pasture, wheat, ploughland and hay meadow with hedgerows, flocks of sheep and herds of cattle, and the London road and two lanes. |

## London

### How to get out into the city
- **The mews behind Ashcombe House** (east of the market, along Ashcombe Row) is now open at both ends:
  - **North end:** it comes out on the ring road round the old streets.
  - **South end:** a new lane runs on down to the south ring road.
- From the ring road, the streets run in every direction to the edge of the city.

### Layout (`scripts/city/city_plan.gd`)
- **Main roads.** Main roads run north–south and east–west about every 200–250 m. Their carriageways are 10 m wide, with 3.2 m pavements.
- **Side streets.** Side streets (7 m wide, 2.4 m pavements) cut each superblock into blocks of 50–85 m.
- **The Thames** (z 575 to 805):
  - It is walled in by the Embankment, with a riverside walk on each bank.
  - The bridges are at Westminster, Blackfriars, London Bridge and one further east.
  - Iron ladders run down the walls. At low tide the river is about waist-deep, so a fall is not fatal.
- **Districts:**
  - **West End:** grand stucco terraces, garden squares, and the park.
  - **The City:** St Paul's, brick shops and offices, Wren churches.
  - **East End:** narrow poor terraces and riverside warehouses.
  - **The north:** suburbs.
  - **South of the river:** Southwark and Lambeth.
- **Every block** has granite kerbs and a raised pavement. Terraces run along every frontage; corner houses have windows on both faces, and corners are often pubs. There are back yards with brick walls, and sometimes a covered way through to them.
- **Buildings** have:
  - sash windows with glazing bars and stone surrounds
  - doorcases, fanlights, steps and area railings
  - shopfronts with gilt signs and awnings
  - slate roofs, chimney stacks with pots, and drainpipes you can climb
- **Everything is generated from one seed**, so it is the same city every time.

### Streaming (`scripts/city/city_streamer.gd`, `city_builder.gd`, `city_geo.gd`)
- **Chunks.** The city is built round the player in 128 m chunks, on background threads.
- **Detail by distance from the player's chunk:**

| Level | Distance (chunks) | What it includes |
|---|---|---|
| 0 | up to 1 | Everything: collision, a navigation mesh for the passers-by and constables, gas lamps (lit by the lamplighter, and counted by the stealth system), shop signs, pipes to climb |
| 1 | up to 2 | Simpler buildings; railings drawn as a band |
| 2 | up to 4 | Building masses, roofs, window panes and chimney stacks |
| Beyond that | the rest of the city | One MultiMesh with one box per terrace (4,400 terraces in all). The terraces of loaded chunks are hidden so the two never overlap. |

- **Draw calls:** each chunk is one mesh, with one draw call per material, plus a single shadow-caster mesh.
- **Occlusion:** each chunk has an occluder built from its building masses, so streets hidden behind buildings aren't drawn.
- **Cost:** a full-detail chunk takes about 0.3 s on a worker thread. The whole view (81 chunks) is about 2.7 million vertices and about 160 MB.
- **Beyond the edge:** the horizon ring of scenery rooftops (`london_skyline.gd`) starts at the city's edge. There is an invisible wall there, so no one can walk off it.
- **Fog:** clear-weather fog was thinned for the long views. Pea-soupers and rain still close it right in.

### People (`scripts/city/city_life.gd`)
- **Passers-by.** Near the player there is a constant flow of passers-by, about 34 at the busiest hour. They come out of one door and walk to another.
  - Their clothes depend on the district.
  - They are all ordinary townsfolk (Civilian), so they can have their pockets picked and they cry "Thief!".
- **Others on the street:**
  - Street sellers cry their wares on the corners.
  - Constables walk beats round the blocks, with lanterns at night.
- **Numbers by time and weather:**
  - The streets are busiest going to and from work.
  - They empty late at night, when the pubs turn out drunks.
  - Rain and snow thin the crowds.
- **Letting go.** People more than 115 m away are let go.

## The hills

- **Size:** `TerrainGenerator.HALF_SIZE` is now 2048, so the map is 4.1 km square.
- **The London road** runs on east through Highgate and Kentish Green to the new east edge, where the signpost to London now stands.
- **Lanes** lead north to Northwold and west to Westcombe.
- **The villages** (`scripts/wilderness/village.gd`):
  - Each has cottages round a green with a pond, a well and a maypole.
  - Cottages are whitewashed, timber-framed, brick or flint, with thatch or tile roofs, and have picket-fenced gardens.
  - Each also has a church with a tower, an inn with its sign, a smithy with a glowing forge, and barns and hay ricks.
  - The village ground follows the road's easy grade.
- **Villagers** (`village_folk.gd`) go about by day: to the well, the green, the smithy, the church on Sunday mornings, and the inn in the evening. They go indoors at night.
- **Farms** (`TerrainGenerator.farm_at`) spread about 400 m round each village:
  - Fields are about 95 × 130 m, of pasture, cut wheat, ploughed land or hay meadow.
  - They are drawn by the terrain shader and edged with hedgerows and oaks.
- **Livestock** (`farm_animals.gd`, `livestock.gd`):
  - Flocks of sheep and small herds of cattle graze the pastures near the player.
  - They are the same animals in the same field each time.
  - They trot away from anyone who runs at them.

## Tests
- `tests/test_city.gd` (32 checks):
  - the size, the plan and the way out through the mews
  - solid roofs, pipes, lamps and signs
  - navigation across chunks
  - passers-by and constables
  - the bridges and the river
  - Southwark and the city's edge
- `tests/test_countryside.gd` (14 checks):
  - the size, the villages and their people
  - the fields and hedgerows, and the livestock
  - the London road to the east edge

## A living world: sky, traffic, birds, crowds

### Sky
`assets/sky/london_sky.gdshader` replaces the old physical sky.

**What it draws:**
- **Daytime:** a deep blue sky that pales to haze at the horizon, the sun with its glow, and silver linings on the clouds.
- **Clouds:** they sit on a curved dome and drift with the wind.
  - **Clear days:** scattered fair-weather cumulus.
  - **Overcast:** broken grey cloud.
  - **Rain and storms:** a dark lid over the whole sky.
- **Dawn and dusk:** warm colours towards the sun.
- **Clear nights:** stars.

**What drives it:**
- `DayNightCycle` sets these every tenth of a second:
  - daylight
  - cloud coverage and darkness from `Weather`
  - fog haze
  - stars
- `WeatherEffects` moves the clouds with the wind.

**Exposure:**
- The daytime exposure target is lower than before.
- Pale paving is toned down so sunlit streets no longer glare.
- There is more fill light from the sky in the shade.

### Traffic (`scripts/city/horse_vehicle.gd`, `city_traffic.gd`)
**The vehicles:**
- **Kinds:** hansom cabs, four-wheeled growlers, carriers' carts, brewers' drays laden with barrels, and two-horse omnibuses carrying advertisements.
- **Details:** trotting horses in harness, turning wheels, and a driver up on the box.

**How they drive:**
- They follow the main roads, keep to the left, and turn at the junctions.
- They queue behind each other.
- They pull up for Harry ("Mind yerself!") and for people in the road.
- They are solid, and push people out of the way.

**How many:**
- About 18 round the player by day, fewer at night and in fog or snow.
- Only a few while Harry is inside the old streets.
- In the hills (`scripts/wilderness/road_traffic.gd`), carts, wagons and the odd cab travel the London road and the village lanes.

### Birds (`scripts/world/bird_life.gd`)
- **Flying flocks:**
  - In the city: pigeons and starlings wheel over the rooftops, and gulls work the Thames.
  - In the hills: rooks.
- **On the ground:** pigeons peck in the streets, and rooks in the fields.
  - Walk or drive at them and they clatter up and away, then settle again a little way off.
- **How they're drawn:** each flock is one draw call, with the wings flapping in the vertex shader.

### Crowds and dogs
- The city streets hold up to about 56 passers-by round the player at the busiest hours.
- Some walk their dogs (`scripts/world/street_dog.gd`), which trot at their owner's heel.

### Tests
`tests/test_life.gd` (16 checks):
- **Sky:** the sky shader is in use, clouds follow the weather and drift with the wind, and daytime is starless.
- **Traffic:** vehicles come in several kinds, drive along, keep to the left, and pull up for Harry.
- **Birds:** flocks are about, and pigeons fly up when approached.
- **Crowds:** the streets are crowded by day, and dogs keep to their owners' heels.
