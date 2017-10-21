import systems;
import system_flags;
import ABEM_data;

tidy class TerritoryScript {
	TerritoryNode@ node;
	set_int inner;
	set_int edges;
	set_int nebulae;

	bool regionDelta = false;
	array<Region@> regions;
	array<Region@> visionPending;
	array<bool> visionPendingOp;

	void postInit(Territory& obj) {
		obj.sightRange = 0.0;
		@node = TerritoryNode();
		node.setOwner(obj.owner);
	}

	void destroy(Territory& obj) {
		node.markForDeletion();
		@node = null;
	}

	void save(Territory& obj, SaveFile& file) {
		uint cnt = regions.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << regions[i];

		cnt = visionPending.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			file << visionPending[i];
			file << visionPendingOp[i];
		}
	}

	void load(Territory& obj, SaveFile& file) {
		uint cnt = 0;
		file >> cnt;
		regions.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			@regions[i] = cast<Region>(file.readObject());

		file >> cnt;
		visionPending.length = cnt;
		visionPendingOp.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			@visionPending[i] = cast<Region>(file.readObject());
			file >> visionPendingOp[i];
		}
	}

	void postLoad(Territory& obj) {
		@node = TerritoryNode();
		node.setOwner(obj.owner);

		for(uint i = 0, cnt = regions.length; i < cnt; ++i) {
			Region@ region = regions[i];
			node.addInner(region.id, region.position, region.radius);
			inner.insert(region.id);

			if (config::AUTO_CLAIM_NEBULAE > 0) {
				if(region.isNebula && region.macronebula is null)
					region.initMacronebula();

				if(region.macronebula !is null && !nebulae.contains(region.macronebula.id)) {
					//print("PostLoad: Adding macronebula " + region.macronebula.id);
					addNebula(obj, region.macronebula);
				}
			}

			if(edges.contains(region.id)) {
				node.removeEdge(region.id);
				edges.erase(region.id);
			}

			//Add edges from this region
			SystemDesc@ desc = getSystem(region.SystemId);
			for(uint i = 0, cnt = desc.adjacent.length; i < cnt; ++i) {
				uint adj = desc.adjacent[i];
				SystemDesc@ other = getSystem(adj);

				if(inner.contains(other.object.id))
					continue;
				if(edges.contains(other.object.id))
					continue;

				if(config::AUTO_CLAIM_NEBULAE > 0 && other.object.isNebula && other.object.macronebula is null)
					other.object.initMacronebula();

				if(config::AUTO_CLAIM_NEBULAE > 0 && other.object.macronebula !is null && !nebulae.contains(other.object.macronebula.id)) {
					//print("PostLoad: Adding adjacent macronebula " + other.object.macronebula.id);
					addNebula(obj, other.object.macronebula);
					continue;
				}
				else {
					edges.insert(other.object.id);
					node.addEdge(other.object.id, other.position, other.radius);
				}
			}
		}

		//Reverse pending vision to get to old state
		for(int i = visionPending.length - 1; i >= 0; --i) {
			Region@ region = visionPending[i];
			if(visionPendingOp[i])
				node.removeInner(region.id);
			else
				node.addInner(region.id, region.position, region.radius);
		}
	}

	void addNebula(Territory& obj, Macronebula@ macronebula) {
		nebulae.insert(macronebula.id);
		macronebula.claimMacronebula(obj);

		for(uint i = 0, cnt = macronebula.nebulaCount; i < cnt; ++i) {
			Region@ nebula = macronebula.nebulae[i];
			//print("Adding nebula ID " + nebula.SystemId + " from macronebula ID " + macronebula.id + " to empire ID " + obj.owner.id + " (" + obj.owner.name + ").");
			nebula.TradeMask |= obj.owner.mask;
			add(obj, nebula);
		}

		addNebulaEdges(obj, macronebula);
	}

	void addNebulaEdges(Territory& obj, Macronebula@ macronebula) {
		for(uint i = 0, cnt = macronebula.edgeCount; i < cnt; ++i) {
			Region@ edge = macronebula.edges[i];
			//print("Checking if edge " + i + " is owned...");
			if(inner.contains(edge.id) || edges.contains(edge.id))
				continue; // Oops, this edge is already part of our territory... moving on.
			//print("Adding unowned edge ID " + edge.SystemId + " from macronebula ID " + macronebula.id + " to empire ID " + obj.owner.id + " (" + obj.owner.name + ").");
			edges.insert(edge.id);
			node.addEdge(edge.id, edge.position, edge.radius);
		}
	}

	bool canRemoveNebula(Territory& obj, Macronebula@ macronebula) {
		if(!nebulae.contains(macronebula.id))
			return true; // We have already removed this nebula after an earlier canRemoveNebula() call, don't bother...

		for(uint i = 0, cnt = macronebula.edgeCount; i < cnt; ++i) {
			Region@ edge = macronebula.edges[i];
			SystemDesc@ desc = getSystem(edge.SystemId);
			if(inner.contains(edge.id)) {
				return false; // At least one of the macronebula's edges is still owned by the empire.
			}
		}
		return true; // None of the macronebula's edges are owned by the empire, we can safely wipe it out.
	}

	void removeNebula(Territory& obj, Macronebula@ macronebula) {
		nebulae.erase(macronebula.id);
		macronebula.unclaimMacronebula(obj);

		removeNebulaEdges(obj, macronebula);

		for(uint i = 0, cnt = macronebula.nebulaCount; i < cnt; ++i) {
			Region@ nebula = macronebula.nebulae[i];
			nebula.TradeMask &= ~obj.owner.mask;
			remove(obj, nebula);
		}
	}

	void removeNebulaEdges(Territory& obj, Macronebula@ macronebula) {
		for(uint i = 0, cnt = macronebula.edgeCount; i < cnt; ++i) {
			Region@ edge = macronebula.edges[i];
			SystemDesc@ desc = getSystem(edge.SystemId);
			bool found = false;
			for(uint j = 0, jcnt = desc.adjacent.length; j < jcnt; ++j) {
				SystemDesc@ chk = getSystem(desc.adjacent[j]);
				if(chk.object.macronebula !is macronebula && inner.contains(chk.object.id)) {
					found = true;
					break;
				}
			}
			if(!found) {
				edges.erase(edge.id);
				node.removeEdge(edge.id);
			}
		}
	}

	double tick(Territory& obj, double time) {
		for(uint i = 0, cnt = visionPending.length; i < cnt; ++i) {
			Region@ region = visionPending[i];
			if(obj.owner is playerEmpire || region.VisionMask & playerEmpire.visionMask != 0) {
				if(visionPendingOp[i])
					node.addInner(region.id, region.position, region.radius);
				else
					node.removeInner(region.id);

				visionPending.removeAt(i);
				visionPendingOp.removeAt(i);
				--i; --cnt;
			}
		}
		return 1.0;
	}

	bool canTradeTo(Region@ region) const {
		return inner.contains(region.id) || edges.contains(region.id);
	}

	uint getRegionCount() const {
		return regions.length;
	}

	Region@ getRegion(uint i) const {
		if(i >= regions.length)
			return null;
		return regions[i];
	}

	void add(Territory& obj, Region@ region) {
		if(inner.contains(region.id)) // Presumably this is a nebula that we already owned, transitioning from a now-removed macronebula.
			return;
		if(obj.owner is playerEmpire || region.VisionMask & playerEmpire.visionMask != 0) {
			node.addInner(region.id, region.position, region.radius);
		}
		else {
			visionPending.insertLast(region);
			visionPendingOp.insertLast(true);
		}

		inner.insert(region.id);
		regions.insertLast(region);
		regionDelta = true;

		if(edges.contains(region.id)) {
			node.removeEdge(region.id);
			edges.erase(region.id);
		}

		if(region.macronebula !is null) {
			return; // Add the macronebula's edges through a more streamlined function.
		}

		//Add edges from this region
		SystemDesc@ desc = getSystem(region.SystemId);
		for(uint i = 0, cnt = desc.adjacent.length; i < cnt; ++i) {
			uint adj = desc.adjacent[i];
			SystemDesc@ other = getSystem(adj);

			if(inner.contains(other.object.id))
				continue;
			if(edges.contains(other.object.id))
				continue;

			if(config::AUTO_CLAIM_NEBULAE > 0 && other.object.macronebula !is null && !nebulae.contains(other.object.macronebula.id))
				addNebula(obj, other.object.macronebula);
			else { // addNebula() will add this edge as well, no need to worry.
				edges.insert(other.object.id);
				node.addEdge(other.object.id, other.position, other.radius);
			}
		}
	}

	void remove(Territory& obj, Region@ region) {
		if(obj.owner is playerEmpire || region.VisionMask & playerEmpire.visionMask != 0) {
			node.removeInner(region.id);
		}
		else {
			visionPending.insertLast(region);
			visionPendingOp.insertLast(false);
		}

		inner.erase(region.id);
		regions.remove(region);
		regionDelta = true;

		if(region.macronebula !is null)
			return; // Remove the macronebula's edges through a more streamlined function. The macronebula itself can never be a territory edge, so the rest of this is irrelevant.

		//Remove edges from this region
		SystemDesc@ desc = getSystem(region.SystemId);
		bool isEdge = false;
		for(uint i = 0, cnt = desc.adjacent.length; i < cnt; ++i) {
			uint adj = desc.adjacent[i];
			SystemDesc@ other = getSystem(adj);

			// This isn't necessarily true, but if we're not adjacent to -any- nebulae,
			// then we want to ignore this condition, so...
			bool adjacentNebulaIsUnowned = false;

			if(other.object.macronebula !is null) {
				// We have already removed this system from the 'inner' list,
				// and if no other edges are on that list we will know we can remove the nebula.
				adjacentNebulaIsUnowned = canRemoveNebula(obj, other.object.macronebula);
				if(config::AUTO_CLAIM_NEBULAE > 0 && adjacentNebulaIsUnowned)
					removeNebula(obj, other.object.macronebula);
			}

			if(inner.contains(other.object.id) && !adjacentNebulaIsUnowned)
				isEdge = true;

			if(!edges.contains(other.object.id))
				continue;

			bool found = false;
			for(uint j = 0, jcnt = other.adjacent.length; j < jcnt; ++j) {
				SystemDesc@ chk = getSystem(other.adjacent[j]);
				if(inner.contains(chk.object.id)) {
					found = true;
					break;
				}
			}

			if(!found) {
				edges.erase(other.object.id);
				node.removeEdge(other.object.id);
			}
		}

		//Check if this should be added back as an edge
		if(isEdge) {
			edges.insert(region.id);
			node.addEdge(region.id, region.position, region.radius);
		}
	}

	void _writeRegions(const Territory& obj, Message& msg) {
		uint cnt = regions.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << regions[i];
	}

	void syncInitial(const Territory& obj, Message& msg) {
		_writeRegions(obj, msg);
	}

	void syncDetailed(const Territory& obj, Message& msg) {
		_writeRegions(obj, msg);
	}

	bool syncDelta(const Territory& obj, Message& msg) {
		if(!regionDelta)
			return false;

		if(regionDelta) {
			msg.write1();
			_writeRegions(obj, msg);
			regionDelta = false;
		}
		else {
			msg.write0();
		}

		return true;
	}
};
