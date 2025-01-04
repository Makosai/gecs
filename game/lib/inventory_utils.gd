## This class is the main class for interacting with the player's inventory.[br]
## It consists of all static methods that are used to interact with any item in any player's inventory.[br]
class_name InventoryUtils

## Uses an item from the player's inventory.[br]
## This is the main way we interact with items in the player's inventory.[br]
## Calls the run_inventory_action method on the item's [Action].[br]
## Parameters:[br]
##   - item: The item [Entity] to use.[br]
##   - player: The player [Entity] using the [C_Item] from the `item`.
static func use_inventory_item(item: Entity, player: Entity):
	var action = get_item_action(item) as InventoryAction
	if action and action.has_method('run_inventory_action'):
		# pass in the item and the player. The action is responsible for removing the item
		action.run_inventory_action([item], player)

## Helper function to handle picking up resources (weapons and items).
static func add_to_inventory(player: Entity, c_item: C_Item, quantity: int, inventory_signal: Signal, active_resource_property: String):
	var new_entity = c_item.make_entity(quantity)
	new_entity.add_relationship(Relationship.new(C_OwnedBy.new(), player))
	ECS.world.add_entity(new_entity, [C_Persistent.new()])
	inventory_signal.emit(new_entity)
	Loggie.debug('Added item to inventory: ', new_entity.name, ' Quantity: ', quantity)
	if not GameState.get(active_resource_property):
		GameState.set(active_resource_property, new_entity)
	consolidate_inventory()
	return true

static func pickup_resource(pickup: Pickup, c_item: Component, inventory_signal: Signal, active_resource_property: String):
	var player = pickup.get_relationship(Relationship.new(C_OwnedBy.new(), Player)).target
	assert(player, 'Player not found')
	if c_item.pickup_action:
		c_item.pickup_action.run_action()
	return add_to_inventory(player, c_item, pickup.quantity, inventory_signal, active_resource_property)

## Adds a weapon to the player's inventory.
static func pickup_weapon(pickup: Pickup):
	return pickup_resource(
		pickup,
		pickup.item_resource,
		GameState.inventory_weapon_added,
		"active_weapon"
	)

## Adds an item to the player's inventory.
static func pickup_item(pickup: Pickup):
	return pickup_resource(
		pickup,
		pickup.item_resource,
		GameState.inventory_item_added,
		"active_item"
	)

## Gets the quantity of the specified item.[br]
## Parameters:[br]
##   - item: The item entity.[br]
## Returns:[br]
##   - The quantity of the item.
static func get_item_quantity(item: Entity) -> int:
	if not item:
		return 0
	var c_qty = item.get_component(C_Quantity) as C_Quantity
	return c_qty.value if c_qty else 1

## Gets the action associated with the item.[br]
## Parameters:[br]
##   - item: The item entity.[br]
## Returns:[br]
##   - The action associated with the item.
static func get_item_action(item: Entity) -> Action:
	var c_item_weapon = get_item_or_weapon(item)
	if c_item_weapon:
		return c_item_weapon.action
	assert(false, 'Item does not have an action')
	return

## Gets the item or weapon component from the entity.[br]
## Parameters:[br]
##   - [item]: The item entity.[br]
## Returns:[br]
##   - The [C_Item] or [C_Weapon] [Component].
static func get_item_or_weapon(item:Entity):
	var c_item = item.get_component(C_Item) as C_Item
	if c_item:
		return c_item
	var c_weapon = item.get_component(C_Weapon) as C_Weapon
	if c_weapon:
		return c_weapon
	return

## Removes a specified quantity of an item from the world.[br]
## If the quantity is 0, the item is removed from the world.[br]
## Since items have no explicit dependency of being in the player's inventory, [br]
## this method can be used to remove items from the world or in an inventory.[br]
## Parameters:[br]
##   - [item]: The item entity to remove.[br]
##   - [remove_quantity]: The quantity to remove.
static func remove_inventory_item(item: Entity, remove_quantity = 1):	
	var c_item_weapon = get_item_or_weapon(item)
	var c_qty = item.get_component(C_Quantity) as C_Quantity
	var quantity = c_qty.value if c_qty else 1
	if c_item_weapon:
		if quantity >= remove_quantity:
			c_qty.value -= remove_quantity
		if c_qty.value == 0:
			item.add_component(C_IsPendingDelete.new())
			if item.has_component(C_IsActiveItem) :
				GameState.active_item = null
			if item.has_component(C_IsActiveWeapon):
				GameState.active_weapon = null

		Loggie.debug('Removing Item', c_item_weapon)
		GameState.inventory_item_removed.emit(item)
	else:
		Loggie.debug('Item does not have a C_Item component')

static func cycle_inventory(current_active: Entity, query_filter: QueryBuilder) -> Entity:
	consolidate_inventory()
	var items = Queries.in_inventory_of_entity(GameState.player).combine(query_filter).combine(Queries.shows_in_quickbar()).execute()
	if items.size() == 0:
		return null
	var index = -1
	if current_active:
		index = items.find(current_active)
	var next_index = (index + 1) % items.size()
	return items[next_index]

## Cycles to the next item in the player's inventory.
static func cycle_inventory_item():
	GameState.active_item = cycle_inventory(GameState.active_item, Queries.is_item())

## Cycles to the next weapon in the player's inventory.
static func cycle_inventory_weapon():
	GameState.active_weapon = cycle_inventory(GameState.active_weapon, Queries.is_weapon())

## Consolidates the player's inventory.[br]
## This will consolidate all items that have the same item component.[br]
## This is useful for when the player picks up multiple items of the same type.[br]
## For example, if the player picks up 3 health potions, this will consolidate them into a single entity with a quantity of 3.
static func consolidate_inventory():
	var inventory_entities = Queries.in_inventory_of_entity(GameState.player).execute()
	var item_quantities = {}
	var entities_to_remove = []

	# Sum quantities for each unique c_item
	for entity in inventory_entities:
		var c_item = get_item_or_weapon(entity)
		if c_item:
			var quantity = get_item_quantity(entity)
			if c_item in item_quantities:
				# Add quantity to existing entry
				item_quantities[c_item]["quantity"] += quantity
				entities_to_remove.append(entity)  # Mark duplicate entity for removal
			else:
				# Create new entry for unique item
				item_quantities[c_item] = {"entity": entity, "quantity": quantity}

	# Remove duplicate entities
	for entity in entities_to_remove:
		ECS.world.remove_entity(entity)

	# Update quantities of remaining entities
	for item_data in item_quantities.values():
		var entity = item_data["entity"]
		var qty = item_data["quantity"]
		entity.add_component(C_Quantity.new(qty))

## Check and see if an entity has a specific item in their inventory.[br]
## Parameters:[br]
##   - [player]: The entity with an inventory.[br]
##   - [c_item]: The item resource to get.
static func get_item(player: Entity, c_item: C_Item) -> Entity:
	var items = Queries.in_inventory_of_entity(player).combine(Queries.is_item()).execute()
	for item in items:
		if c_item.equals(item.get_component(C_Item)):
			return item
	return null
