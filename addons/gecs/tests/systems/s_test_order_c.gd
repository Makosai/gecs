class_name S_TestOrderC
extends System
const NAME = 'S_TestOrderC'
func deps():
	return {
		Runs.After: [S_TestOrderB],
		Runs.Before: [S_TestOrderD],
	}

func query():
	return ECS.world.query.with_all([C_TestOrderComponent])

func process(entity: Entity, delta: float):
	var comp = entity.get_component(C_TestOrderComponent)
	comp.execution_log.append("C")
	comp.value += 100
