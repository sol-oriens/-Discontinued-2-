// Infrastructure
// ------
// Manages building basic structures in newly colonized or weakened systems
// to support the Military or Colonization components.
//
import empire_ai.weasel.WeaselAI;

import empire_ai.weasel.Development;
import empire_ai.weasel.Construction;
import empire_ai.weasel.Development;
import empire_ai.weasel.Orbitals;
import empire_ai.weasel.Systems;

import ABEM_data;

import util.Lookup;

enum SystemArea {
  SA_Core,
  SA_Tradable,
};

enum ResourcePreference {
  RP_None,
  RP_FoodWater,
  RP_Level0,
  RP_Level1,
  RP_Level2,
  RP_Level3,
  RP_Scalable,
}

enum BuildAction {
  BA_BuildOutpost,
}

enum BuildLocation {
  BL_InSystem,
  BL_AtSystemEdge,
  BL_AtBestPlanet,
};

final class OrbitalOrder {
  BuildOrbital@ info;

  double expires = INFINITY;

  OrbitalOrder() {}

  OrbitalOrder(BuildOrbital@ info) {
    @this.info = info;
  }

  void save(Infrastructure& infrastructure, SaveFile& file) {
    infrastructure.construction.saveConstruction(file, info);
    file << expires;
  }

  void load(Infrastructure& infrastructure, SaveFile& file) {
    @info = cast<BuildOrbital>(infrastructure.construction.loadConstruction(file));
    file >> expires;
  }
}

final class NextAction {
  SystemCheck@ sys;
  BuildAction action;
  BuildLocation loc;

  NextAction() {}

  NextAction(SystemCheck@ sys, BuildAction action, BuildLocation loc) {
    @this.sys = sys;
    this.action = action;
    this.loc = loc;
  }
};

final class SystemCheck {
  SystemAI@ ai;
  Region@ region;
  OrbitalAI@ orbital;

  array<OrbitalOrder@> orders;

  double checkInTime = 0.0;
  double weight = 0.0;
  bool isUnderAttack = false;
  int nebulaFlag = -1;

  SystemCheck() {}

  SystemCheck(Infrastructure& infrastructure, SystemAI@ ai) {
    @this.ai = ai;
    @this.region = ai.obj;
    checkInTime = gameTime;
    if (region.isNebula)
      nebulaFlag = infrastructure.identifyNebula(region);
  }

  void save(Infrastructure& infrastructure, SaveFile& file) {
    infrastructure.systems.saveAI(file, ai);

    uint cnt = orders.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			orders[i].save(infrastructure, file);

    file << checkInTime;
    file << weight;
    file << isUnderAttack;
    file << nebulaFlag;
  }

  void load(Infrastructure& infrastructure, SaveFile& file) {
    @ai = infrastructure.systems.loadAI(file);
    @region = ai.obj;

    uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
      OrbitalOrder@ order = OrbitalOrder();
			order.load(infrastructure, file);
      orders.insertLast(order);
		}
    file >> checkInTime;
    file >> weight;
    file >> isUnderAttack;
    file >> nebulaFlag;
  }

  void tick(AI& ai, Infrastructure& infrastructure, double time) {
    isUnderAttack = region.ContestedMask & ai.mask != 0;

    /*if (isUnderAttack && isBuilding()) {
      //TODO: Cancel order
    }*/
    if (isBuilding()) {
      for (int i = 0, cnt = orders.length; i < cnt; ++i) {
        OrbitalOrder@ order = orders[i];
        if (order.info.completed) {
          //ai.print("order completed");
          @orbital = infrastructure.orbitals.getInSystem(ai.defs.TradeOutpost, region);
          if (orbital !is null) {
            orders.remove(order);
            @order = null;
          }
        }
        else if (!order.info.started && order.expires < gameTime) {
          //ai.print("order expired, gameTime =" + gameTime);
          orders.remove(order);
          @order = null;
        }
        if (orbital !is null) {
          if(!orbital.obj.valid) {
            @orbital = null;
            orders.remove(order);
    				@order = null;
    			}
        }
      }
    }
  }

  void focusTick(AI& ai, Infrastructure& infrastructure, double time) {
  }

  double check(AI& ai) {
    weight = 0.0;
    //Dangerous nebulae should always be ignored
    if (nebulaFlag != -1) {
      if (Lookup(nebulaFlag).isIn(array<int> = {
          METREON_NEBULA_FLAG,
          RADIOACTIVE_NEBULA_FLAG
        })) {
        //Not in dangerous nebulae
        return weight;
      }
    }
    //Systems under attack are bottom priority for now
    if (isUnderAttack)
				return weight;
    //Hostile systems are bottom priority until cleared
    if (this.ai.seenPresent & ai.enemyMask != 0)
      return weight;
    if (this.ai.pickupProtectors.length > 0)
      return weight;
    //Start weighting
    double sysWeight = 1.0;
    //Oldest systems come first
    sysWeight /= checkInTime / 60.0;
    //The home system is a priority
    if (region !is ai.empire.HomeSystem)
      sysWeight /= 2.0;
    else if (nebulaFlag != -1) {
      //The best nebulae
      if (Lookup(nebulaFlag).isIn(array<int> = {
          TACHYON_NEBULA_FLAG
        })) {
          sysWeight /= 1.9;
      }
      //The average nebulae
      else if (Lookup(nebulaFlag).isIn(array<int> = {
          CERULEAN_NEBULA_FLAG,
          ECONOMIC_NEBULA_FLAG,
          METAPHASIC_NEBULA_FLAG,
          MUTARA_NEBULA_FLAG,
          TYPE_1_NEBULA_FLAG
        })) {
          sysWeight /= 1.5;
      }
      //Meh
      else if (Lookup(nebulaFlag).isIn(array<int> = {
          EMPTY_SPACE_NEBULA_FLAG
        })) {
          sysWeight /= 1.1;
      }
    }
    weight = 1.0 * sysWeight;
    return weight;
  }

  void buildInSystem(Construction& construction, const OrbitalModule@ module, double priority = 1.0, bool force = false, double delay = 600) {
    vec3d pos = region.position;
    vec2d offset = random2d(region.radius * 0.4, region.radius * 0.7);
    pos.x += offset.x;
    pos.z += offset.y;

    BuildOrbital@ info = construction.buildOrbital(module, pos, priority, force);
    OrbitalOrder@ order = OrbitalOrder(info);
    order.expires = gameTime + delay;
    orders.insertLast(order);
  }

  void buildAtSystemEdge(Construction& construction, const OrbitalModule@ module, double priority = 1.0, bool force = false, double delay = 600) {
    vec3d pos = region.position;
    vec2d offset = random2d(region.radius * 0.8, region.radius * 0.9);
    pos.x += offset.x;
    pos.z += offset.y;

    BuildOrbital@ info = construction.buildOrbital(module, pos, priority, force);
    OrbitalOrder@ order = OrbitalOrder(info);
    order.expires = gameTime + delay;
    orders.insertLast(order);
  }

  void buildAtPlanet(Construction& construction, Planet& planet, const OrbitalModule@ module, double priority = 1.0, bool force = false, double delay = 600) {
    BuildOrbital@ info = construction.buildLocalOrbital(module, planet, priority, force);
    OrbitalOrder@ order = OrbitalOrder(info);
    order.expires = gameTime + delay;
    orders.insertLast(order);
  }

  bool isBuilding() {
    return orders.length > 0;
  }

  bool isBuildingOrbital(const OrbitalModule@ module) {
    for (uint i = 0, cnt = orders.length; i < cnt; ++i) {
      if (orders[i].info.module is module)
        return true;
    }
    return false;
  }
};

final class Infrastructure : AIComponent {
  const ResourceClass@ foodClass, waterClass, scalableClass;

  Development@ development;
  Construction@ construction;
  Orbitals@ orbitals;
	Systems@ systems;

  array<SystemCheck@> ownedSystems;
  array<SystemCheck@> outsideSystems;

  SystemCheck@ homeSystem;
  NextAction@ next;

  uint maxOrdersPerSys = 1;
  uint maxOrdersPerSysOutside = 1;
  uint maxOrdersTotal = 3;

  void create() {
    @development = cast<Development>(ai.development);
    @construction = cast<Construction>(ai.construction);
		@orbitals = cast<Orbitals>(ai.orbitals);
		@systems = cast<Systems>(ai.systems);

    @foodClass = getResourceClass("Food");
		@waterClass = getResourceClass("WaterType");
		@scalableClass = getResourceClass("Scalable");
	}

  void save(SaveFile& file) {
    uint cnt = ownedSystems.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			ownedSystems[i].save(this, file);
    cnt = outsideSystems.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			outsideSystems[i].save(this, file);
  }

  void load(SaveFile& file) {
    uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
      SystemCheck@ sys = SystemCheck();
			sys.load(this, file);
      ownedSystems.insertLast(sys);
		}
    cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
      SystemCheck@ sys = SystemCheck();
			sys.load(this, file);
      outsideSystems.insertLast(sys);
		}
  }

  void start() {
  }

  void tick(double time) override {
    SystemCheck@ sys;
    //Perform routine duties
    for (uint i = 0, cnt = ownedSystems.length; i < cnt; ++i) {
      @sys = ownedSystems[i];
      sys.tick(ai, this, time);
    }
    for (uint i = 0, cnt = outsideSystems.length; i < cnt; ++i) {
      @sys = outsideSystems[i];
      sys.tick(ai, this, time);
    }
  }

  void focusTick(double time) override {
    SystemCheck@ sys;

    double bestWeight = 0.0;
    double bestWeightForOutpost = 0.0;
    //print("current total orders: " + getTotalOrders());
    //Find out which new systems need attention
    //ai.print("owned systems checked: " + ownedSystems.length);
    for(uint i = 0, cnt = systems.owned.length; i < cnt; ++i) {
      if (!isInCheck(systems.owned[i].obj, ownedSystems)) {
        @sys = SystemCheck(this, systems.owned[i]);
        //ai.print("adding owned system");
        ownedSystems.insertLast(sys);
      }
    }
    //Check if owned systems need anything
    for (uint i = 0, cnt = ownedSystems.length; i < cnt; ++i) {
      @sys = ownedSystems[i];
      //Check if any system was lost
      if (isMissing(sys.region, systems.owned)) {
        //ai.print("removing owned system");
        ownedSystems.remove(sys);
        @sys = null;
      }
      if (sys is null)
        break;
      //Evaluate current weight
      double w = sys.check(ai);
      if (w > bestWeight)
        bestWeight = w;
      //Don't do anything if the system is under attack
      if (!sys.isUnderAttack) {
        //Check if we already have something being built, we don't want to build too much
        //TODO: handle evaluation
        //ai.print("orders for owned system at index " + i + ": " + sys.orders.length);
        if (getTotalOrders() < maxOrdersTotal && sys.orders.length < maxOrdersPerSys) {
          //Find out if we need an outpost
          BuildLocation loc;
          if (!hasOutpost(sys.region) && shouldHaveOutpost(sys, SA_Core, loc) && !sys.isBuildingOrbital(ai.defs.TradeOutpost)) {
            if (w > bestWeightForOutpost) {
              bestWeightForOutpost = w;
              @next = NextAction(sys, BA_BuildOutpost, loc);
              //ai.print("outpost ordered for owned system");
            }
          }
        }
      }
      //Perform routine duties
      sys.focusTick(ai, this, time);
    }
    //Check if systems in tradable area need anything
    //ai.print("systems outside border: " + systems.outsideBorder.length);
    for (uint i = 0, cnt = outsideSystems.length; i < cnt; ++i) {
      @sys = outsideSystems[i];
      //Check if borders have changed
      if (isMissing(sys.region, systems.outsideBorder)) {
        //ai.print("removing outside system");
        outsideSystems.remove(sys);
        @sys = null;
      }
      //Check if we already have something being built, we don't want to build too much
      //TODO: handle evaluation
      if (sys is null)
        break;
        //Evaluate current weight
        double w = sys.check(ai);
        if (w > bestWeight)
          bestWeight = w;
      //ai.print("orders for outside system at index " + i + ": " + sys.orders.length);
      if (getTotalOrders() < maxOrdersTotal && sys.orders.length < maxOrdersPerSysOutside) {
        //Find out if we need an outpost
        BuildLocation loc;
        if (!hasOutpost(sys.region) && shouldHaveOutpost(sys, SA_Tradable, loc) && !sys.isBuildingOrbital(ai.defs.TradeOutpost)) {
          if (w > bestWeightForOutpost) {
            bestWeightForOutpost = w;
            @next = NextAction(sys, BA_BuildOutpost, loc);
            //ai.print("outpost ordered for outside system");
          }
        }
      }
      //Perform routine duties
      sys.focusTick(ai, this, time);
    }
    //Find out which new systems need attention
    //ai.print("outside systems checked: " + outsideSystems.length);
    for(uint i = 0, cnt = systems.outsideBorder.length; i < cnt; ++i) {
      if (!isInCheck(systems.outsideBorder[i].obj, outsideSystems)) {
        @sys = SystemCheck(this, systems.outsideBorder[i]);
        //ai.print("adding outside system");
        outsideSystems.insertLast(sys);
      }
    }
    //Execute our next action if there is one
    if (next !is null) {
      Object@ obj;
      @sys = next.sys;
      switch(next.action) {
        case BA_BuildOutpost:
          switch(next.loc) {
            case BL_InSystem:
              sys.buildInSystem(construction, ai.defs.TradeOutpost);
              //ai.print("building in system");
              break;
            case BL_AtSystemEdge:
              sys.buildAtSystemEdge(construction, ai.defs.TradeOutpost);
              //ai.print("building at system edge");
              break;
            case BL_AtBestPlanet:
                @obj = getBestPlanet(sys);
                if (obj !is null) {
                  sys.buildAtPlanet(construction, cast<Planet>(obj), ai.defs.TradeOutpost);
                  //ai.print("building at best planet");
                }
              break;
            default:
              ai.print("ERROR: undefined infrastructure building location for outpost");
          }
          break;
      }
      @next = null;
    }
  }

  bool isInCheck(Region& region, array<SystemCheck@> systems) {
    for (uint i = 0, cnt = systems.length; i < cnt; ++i) {
      if (systems[i].region is region)
        return true;
    }
    return false;
  }

  bool isMissing(const Region& region, array<SystemAI@> systems) {
    for(uint i = 0, cnt = systems.length; i < cnt; ++i) {
      if (systems[i].obj is region)
        return false;
    }
    return true;
  }

  bool shouldHaveOutpost(SystemCheck& sys, SystemArea area, BuildLocation&out loc) {
    loc = BL_InSystem;

    uint presentMask = sys.ai.seenPresent;
    //Make sure we did not previously built an outpost here
    if (hasOutpost(sys.region))
      return false;
    //Hostile systems should be ignored until cleared
    if (presentMask & ai.enemyMask != 0)
      return false;
    if (sys.ai.pickupProtectors.length > 0)
      return false;
    //Inhabited systems should be ignored if we're not aggressive
    if(!ai.behavior.colonizeNeutralOwnedSystems && (presentMask & ai.neutralMask) != 0)
      return false;
    if(!ai.behavior.colonizeAllySystems && (presentMask & ai.allyMask) != 0)
      return false;
    //Nebulae should have an outpost so we can expand our territory beyond them
    if (sys.region.isNebula) {
      int flag = identifyNebula(sys.region);
      if (Lookup(flag).isIn(array<int> = {
          METREON_NEBULA_FLAG,
          RADIOACTIVE_NEBULA_FLAG
        })) {
        //Not in dangerous nebulae
        return false;
      }
      loc = BL_AtSystemEdge;
      return true;
    }
    else {
      Planet@ planet;
      ResourceType@ type;

      switch(area) {
        //Owned systems should have an outpost
        case SA_Core:
          if (sys.ai.planets.length > 0)
            loc = BL_AtBestPlanet;
          return true;
        case SA_Tradable:
        //Outside systems might have an outpost if they are of some interest
          if (sys.ai.planets.length > 0) {
            loc = BL_AtBestPlanet;
            @planet = getBestPlanet(sys, type);
            if (planet is null)
              break;
            //The best planet is barren, the system needs an outpost to allow expansion
            int resId = planet.primaryResourceType;
            if (resId == -1)
              return true;
            //The best planet has either a scalable or level 3 or 2 resource, the system should have an outpost
            if (type !is null && (type.cls is scalableClass || type.level == 3 || type.level == 2))
              return true;
          }
          return false;
        default:
          return false;
      }
    }
    return false;
  }

  bool hasOutpost(Region@ region) {
    return orbitals.haveInSystem(ai.defs.TradeOutpost, region);
  }

  uint getTotalOrders() {
    uint total = 0;
    for (uint i = 0, cnt = ownedSystems.length; i < cnt; ++i) {
      total += ownedSystems[i].orders.length;
    }
    for (uint i = 0, cnt = outsideSystems.length; i < cnt; ++i) {
      total += outsideSystems[i].orders.length;
    }
    return total;
  }

  int identifyNebula(Region@ region) {
    if (region.getSystemFlag(ai.empire, CERULEAN_NEBULA_FLAG)) {
      //ai.print("identified a cerulean nebula");
      return CERULEAN_NEBULA_FLAG;
    }
    else if (region.getSystemFlag(ai.empire, ECONOMIC_NEBULA_FLAG)) {
      //ai.print("identified an economic nebula");
      return ECONOMIC_NEBULA_FLAG;
    }
    else if (region.getSystemFlag(ai.empire, EMPTY_SPACE_NEBULA_FLAG)) {
      //ai.print("identified empty space");
      return EMPTY_SPACE_NEBULA_FLAG;
    }
    else if (region.getSystemFlag(ai.empire, METAPHASIC_NEBULA_FLAG)) {
      //ai.print("identified a metaphasic nebula");
      return METAPHASIC_NEBULA_FLAG;
    }
    else if (region.getSystemFlag(ai.empire, METREON_NEBULA_FLAG)) {
      //ai.print("identified a metreon nebula");
      return METREON_NEBULA_FLAG;
    }
    else if (region.getSystemFlag(ai.empire, MUTARA_NEBULA_FLAG)) {
      //ai.print("identified a mutara nebula");
      return MUTARA_NEBULA_FLAG;
    }
    else if (region.getSystemFlag(ai.empire, RADIOACTIVE_NEBULA_FLAG)) {
      //ai.print("identified a radioactive nebula");
      return RADIOACTIVE_NEBULA_FLAG;
    }
    else if (region.getSystemFlag(ai.empire, TACHYON_NEBULA_FLAG)) {
      //ai.print("identified a tachyon nebula");
      return TACHYON_NEBULA_FLAG;
    }
    else if (region.getSystemFlag(ai.empire, TYPE_1_NEBULA_FLAG)) {
      //ai.print("identified a type 1 nebula");
      return TYPE_1_NEBULA_FLAG;
    }
    return NEBULA_FLAG;
  }

  Planet@ getBestPlanet(SystemCheck sys) {
    ResourceType@ type;
    return getBestPlanet(sys, type);
  }

  Planet@ getBestPlanet(SystemCheck sys, const ResourceType@ resourceType) {
    Planet@ bestPlanet, planet;
    ResourcePreference bestResource = RP_None;

    if (sys.region is ai.empire.HomeSystem) {
      //The homeworld if there is one
      @planet = cast<Planet>(ai.empire.Homeworld);
      if (planet !is null)
        return planet;
    }

    for (uint i = 0, cnt = sys.ai.planets.length; i < cnt; ++i) {
      @planet = sys.ai.planets[i];
      int resId = planet.primaryResourceType;
      if (resId == -1)
        continue;

      const ResourceType@ type = getResource(resId);
      //The first scalable resource
      if (type.cls is scalableClass) {
        @resourceType = type;
        return planet;
      }
      //The first level 3 resource
      if (type.level == 3) {
        bestResource = RP_Level3;
        @resourceType = type;
        @bestPlanet = planet;
      }
      //The first level 2 resource
      else if (type.level == 2 && RP_Level2 > bestResource) {
        bestResource = RP_Level2;
        @resourceType = type;
        @bestPlanet = planet;
      }
      //The first level 1 resource
      else if (type.level == 1 && RP_Level1 > bestResource) {
        bestResource = RP_Level1;
        @resourceType = type;
        @bestPlanet = planet;
      }
      //The first level 0 resource except food and water
      else if (type.level == 0 && type.cls !is foodClass && type.cls !is waterClass && RP_Level0 > bestResource) {
        bestResource = RP_Level0;
        @resourceType = type;
        @bestPlanet = planet;
      }
      //The first food or water resource
      else if ((type.cls is foodClass || type.cls is waterClass) && RP_Level0 > bestResource) {
        bestResource = RP_FoodWater;
        @resourceType = type;
        @bestPlanet = planet;
      }
      else if (i == sys.ai.planets.length - 1 && bestPlanet is null) {
        @resourceType = type;
        @bestPlanet = planet;
      }
    }
    if (bestPlanet is null)
      return planet;
    return bestPlanet;
  }
};

AIComponent@ createInfrastructure() {
	return Infrastructure();
}
