// Infrastructure
// ------
// Manages building basic structures in newly colonized or weakened systems
// to support the Military or Colonization components.
//
import empire_ai.weasel.WeaselAI;

import empire_ai.weasel.Development;
import empire_ai.weasel.Construction;
import empire_ai.weasel.Budget;
import empire_ai.weasel.Orbitals;
import empire_ai.weasel.Systems;
import empire_ai.weasel.Planets;

import ABEM_data;
import util.lookup;

from statuses import getStatusID;

enum ResourcePreference {
  RP_None,
  RP_FoodWater,
  RP_Level0,
  RP_Level1,
  RP_Level2,
  RP_Level3,
  RP_Scalable,
};

enum SystemArea {
  SA_Core,
  SA_Tradable,
};

enum SystemBuildAction {
  BA_BuildOutpost,
};

enum PlanetBuildAction {
  BA_BuildMoonBase,
};

enum SystemBuildLocation {
  BL_InSystem,
  BL_AtSystemEdge,
  BL_AtBestPlanet,
};

final class OwnedSystemEvents : IOwnedSystemEvents {
  Infrastructure@ infrastructure;

  OwnedSystemEvents(Infrastructure& infrastructure) {
     @this.infrastructure = infrastructure;
  }

  void onOwnedSystemAdded(SystemAI& ai) {
    infrastructure.registerOwnedSystemAdded(ai);
  }

  void onOwnedSystemRemoved(SystemAI& ai) {
    infrastructure.registerOwnedSystemRemoved(ai);
  }
};

final class OutsideBorderSystemEvents : IOutsideBorderSystemEvents {
  Infrastructure@ infrastructure;

  OutsideBorderSystemEvents(Infrastructure& infrastructure) {
    @this.infrastructure = infrastructure;
  }

  void onOutsideBorderSystemAdded(SystemAI& ai) {
    infrastructure.registerOutsideBorderSystemAdded(ai);
  }

  void onOutsideBorderSystemRemoved(SystemAI& ai) {
    infrastructure.registerOutsideBorderSystemRemoved(ai);
  }
};

final class PlanetEvents : IPlanetEvents {
  Infrastructure@ infrastructure;

  PlanetEvents(Infrastructure& infrastructure) {
    @this.infrastructure = infrastructure;
  }

  void onPlanetAdded(PlanetAI& ai) {
    infrastructure.registerPlanetAdded(ai);
  }

  void onPlanetRemoved(PlanetAI& ai) {
    infrastructure.registerPlanetRemoved(ai);
  }
};

final class Order {
  private AllocateConstruction@ _construction;

  double expires = INFINITY;

  Order() {}

  Order(AllocateConstruction@ construction) {
    @_construction = construction;
  }

  bool get_isInProgress() const {
    return _construction.started;
  }

  bool get_isComplete() const {
    return _construction.completed;
  }

  AllocateConstruction@ get_info() const {
    return _construction;
  }

  void save(Infrastructure& infrastructure, SaveFile& file) {
    file << _construction.id;
    file << expires;
  }

  void load(Infrastructure& infrastructure, SaveFile& file) {
    int id = - 1;
    file >> id;
    if (id != -1) {
      for (uint i = 0, cnt = infrastructure.construction.allocations.length; i < cnt; ++i) {
        if (infrastructure.construction.allocations[i].id == id) {
          @_construction = infrastructure.construction.allocations[i];
        }
      }
    }
    file >> expires;
  }
};

final class PlanetOrder {
  private ConstructionRequest@ _construction;

  double expires = INFINITY;

  PlanetOrder() {}

  PlanetOrder(ConstructionRequest@ construction) {
    @_construction = construction;
  }

  bool get_isInProgress() const {
    return _construction.built;
  }

  bool get_isComplete() const {
    return _construction.completed;
  }

  ConstructionRequest@ get_info() const {
    return _construction;
  }

  void save(Infrastructure& infrastructure, SaveFile& file) {
    file << _construction.id;
    file << expires;
  }

  void load(Infrastructure& infrastructure, SaveFile& file) {
    int id = - 1;
    file >> id;
    if (id != -1) {
      for (uint i = 0, cnt = infrastructure.planets.constructionRequests.length; i < cnt; ++i) {
        if (infrastructure.planets.constructionRequests[i].id == id) {
          @_construction = infrastructure.planets.constructionRequests[i];
        }
      }
    }
    file >> expires;
  }
};

class NextAction {
  double priority = 1.0;
  bool force = false;
  bool critical = false;
};

final class SystemAction : NextAction {
  private SystemCheck@ _sys;
  private SystemBuildAction _action;
  private SystemBuildLocation _loc;

  SystemAction(SystemCheck& sys, SystemBuildAction action, SystemBuildLocation loc) {
    @_sys = sys;
    _action = action;
    _loc = loc;
  }

  SystemCheck@ get_sys() const { return _sys; }
  SystemBuildAction get_action() const { return _action; }
  SystemBuildLocation get_loc() const { return _loc; }
};

final class PlanetAction : NextAction {
  private PlanetCheck@ _pl;
  private PlanetBuildAction _action;

  PlanetAction(PlanetCheck& pl, PlanetBuildAction action) {
    @_pl = pl;
    _action = action;
  }

  PlanetCheck@ get_pl() const { return _pl; }
  PlanetBuildAction get_action() const { return _action; }
};

final class SystemCheck {
  SystemAI@ ai;

  array<Order@> orders;

  double _checkInTime = 0.0;
  double _weight = 0.0;
  bool _isUnderAttack = false;
  int _nebulaFlag = -1;

  SystemCheck() {}

  SystemCheck(Infrastructure& infrastructure, SystemAI& ai) {
    @this.ai = ai;
    _checkInTime = gameTime;
    if (ai.obj.isNebula)
      _nebulaFlag = infrastructure.identifyNebula(ai.obj);
  }

  double get_checkInTime() const { return _checkInTime; }
  double get_weight() const { return _weight; }
  bool get_isUnderAttack() const { return _isUnderAttack; }
  bool get_isBuilding() const { return orders.length > 0; }

  void save(Infrastructure& infrastructure, SaveFile& file) {
    infrastructure.systems.saveAI(file, ai);

    uint cnt = orders.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			orders[i].save(infrastructure, file);

    file << _checkInTime;
    file << _weight;
    file << _isUnderAttack;
    file << _nebulaFlag;
  }

  void load(Infrastructure& infrastructure, SaveFile& file) {
    @ai = infrastructure.systems.loadAI(file);

    uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
      Order@ order = Order();
			order.load(infrastructure, file);
      orders.insertLast(order);
		}
    file >> _checkInTime;
    file >> _weight;
    file >> _isUnderAttack;
    file >> _nebulaFlag;
  }

  void tick(AI& ai, Infrastructure& infrastructure, double time) {
    OrbitalAI@ orbital;
    _isUnderAttack = this.ai.obj.ContestedMask & ai.mask != 0;
    /*if (_isUnderAttack && isBuilding()) {
      //TODO: Cancel order
    }*/
    if (isBuilding) {
      for (int i = 0, cnt = orders.length; i < cnt; ++i) {
        Order@ order = orders[i];
        if (order.isComplete) {
          if (infrastructure.log)
            ai.print("order complete");
          orders.remove(order);
          @order = null;
        }
        else if (!order.isInProgress && order.expires < gameTime) {
          if (infrastructure.log)
            ai.print("order expired, gameTime = " + gameTime);
          orders.remove(order);
          @order = null;
        }
      }
    }
  }

  void focusTick(AI& ai, Infrastructure& infrastructure, double time) {
  }

  double check(AI& ai) {
    _weight = 0.0;
    //Dangerous nebulae should always be ignored
    if (_nebulaFlag != -1) {
      if (Lookup(_nebulaFlag).isIn(array<int> = {
          METREON_NEBULA_FLAG,
          RADIOACTIVE_NEBULA_FLAG
        })) {
        //Not in dangerous nebulae
        return _weight;
      }
    }
    //Systems under attack are bottom priority for now
    if (_isUnderAttack)
				return _weight;
    //Hostile systems are bottom priority until cleared
    if (this.ai.seenPresent & ai.enemyMask != 0)
      return _weight;
    if (this.ai.pickupProtectors.length > 0)
      return _weight;
    //Start weighting
    double sysWeight = 1.0;
    //Oldest systems come first
    sysWeight /= (_checkInTime + 60.0) / 60.0;
    //The home system is a priority
    if (this.ai.obj is ai.empire.HomeSystem)
      sysWeight *= 2.0;
    else if (_nebulaFlag != -1) {
      //The best nebulae
      if (Lookup(_nebulaFlag).isIn(array<int> = {
          TACHYON_NEBULA_FLAG
        })) {
          sysWeight *= 1.8;
      }
      //The average nebulae
      else if (Lookup(_nebulaFlag).isIn(array<int> = {
          CERULEAN_NEBULA_FLAG,
          ECONOMIC_NEBULA_FLAG,
          METAPHASIC_NEBULA_FLAG,
          MUTARA_NEBULA_FLAG,
          TYPE_1_NEBULA_FLAG
        })) {
          sysWeight *= 1.5;
      }
      //Meh
      else if (Lookup(_nebulaFlag).isIn(array<int> = {
          EMPTY_SPACE_NEBULA_FLAG
        })) {
          sysWeight *= 0.5;
      }
    }
    _weight = 1.0 * sysWeight;
    return _weight;
  }

  void buildInSystem(Infrastructure& infrastructure, Construction& construction, const OrbitalModule@ module, double priority = 1.0, bool force = false, double delay = 600) {
    vec3d pos = ai.obj.position;
    vec2d offset = random2d(ai.obj.radius * 0.4, ai.obj.radius * 0.7);
    pos.x += offset.x;
    pos.z += offset.y;

    BuildOrbital@ orbital = construction.buildOrbital(module, pos, priority, force);
    Order@ order = Order(orbital);
    order.expires = gameTime + delay;
    orders.insertLast(order);
  }

  void buildAtSystemEdge(Infrastructure& infrastructure, Construction& construction, const OrbitalModule@ module, double priority = 1.0, bool force = false, double delay = 600) {
    vec3d pos = ai.obj.position;
    vec2d offset = random2d(ai.obj.radius * 0.8, ai.obj.radius * 0.9);
    pos.x += offset.x;
    pos.z += offset.y;

    BuildOrbital@ orbital = construction.buildOrbital(module, pos, priority, force);
    Order@ order = Order(orbital);
    order.expires = gameTime + delay;
    orders.insertLast(order);
  }

  void buildAtPlanet(Infrastructure& infrastructure, Construction& construction, Planet& planet, const OrbitalModule@ module, double priority = 1.0, bool force = false, double delay = 600) {
    BuildOrbital@ orbital = construction.buildLocalOrbital(module, planet, priority, force);
    Order@ order = Order(orbital);
    order.expires = gameTime + delay;
    orders.insertLast(order);
  }
};

class PlanetCheck {
  PlanetAI@ ai;

  array<PlanetOrder@> orders;

  private double _checkInTime = 0.0;
  private double _weight = 0.0;
  private bool _isGasGiant = false;

  PlanetCheck() {}

  PlanetCheck(Infrastructure& infrastructure, PlanetAI& ai) {
    @this.ai = ai;
    _checkInTime = gameTime;

    int resId = this.ai.obj.primaryResourceType;
    if (resId > -1) {
      const ResourceType@ type = getResource(resId);
      if (type.ident == "RareGases")
        _isGasGiant = true;
    }
  }

  double get_checkInTime() const { return _checkInTime; }
  double get_weight() const { return _weight; }
  bool get_isGasGiant() const { return _isGasGiant; }
  bool get_isBuilding() const { return orders.length > 0; }

  void save(Infrastructure& infrastructure, SaveFile& file) {
    infrastructure.planets.saveAI(file, ai);

    uint cnt = orders.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			orders[i].save(infrastructure, file);

    file << _checkInTime;
    file << _weight;
    file << _isGasGiant;
  }

  void load(Infrastructure& infrastructure, SaveFile& file) {
    @ai = infrastructure.planets.loadAI(file);

    uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
      PlanetOrder@ order = PlanetOrder();
			order.load(infrastructure, file);
      orders.insertLast(order);
		}
    file >> _checkInTime;
    file >> _weight;
    file >> _isGasGiant;
  }

  void tick(AI& ai, Infrastructure& infrastructure, double time) {
    if (isBuilding) {
      for (int i = 0, cnt = orders.length; i < cnt; ++i) {
        PlanetOrder@ order = orders[i];
        if (order.isComplete) {
          if (infrastructure.log)
            ai.print("planet order complete");
          orders.remove(order);
          @order = null;
        }
        else if (!order.isInProgress && order.expires < gameTime) {
          if (infrastructure.log)
            ai.print("planet order expired, gameTime = " + gameTime);
          orders.remove(order);
          @order = null;
        }
      }
    }
  }

  void focusTick(AI& ai, Infrastructure& infrastructure, double time) {
  }

  double check(AI& ai, Infrastructure& infrastructure) {
    _weight = 0.0;

    //Planets in systems under attack are bottom priority for now
    auto@ sys = getSystem(infrastructure);
    if (sys !is null) {
      if (sys._isUnderAttack)
  				return _weight;
    }
    //Start weighting
    double plWeight = 1.0;
    //Oldest planets come first
    plWeight /= (_checkInTime + 60.0) / 60.0;
    //ai.print(this.ai.obj.name + ": checkInTime: " + _checkInTime + " weight: " + plWeight);
    //The homeworld is a priority
    if (this.ai.obj is ai.empire.Homeworld)
      plWeight *= 2.0;
    else {
      //Gas giants with no moon base are a priority, especially if they have been colonized for a while
      if (isGasGiant && this.ai.obj.getStatusStackCountAny(infrastructure.moonBaseStatusId) == 0) {
        plWeight *= 2.0 * (_checkInTime + 60.0) / 60.0;
        //ai.print(this.ai.obj.name + ": gas giant weight bonus: " + plWeight);
        /*plWeight /= _checkInTime / 60.0;
        ai.print(this.ai.obj.name + ": gas giant checkInTime: " + _checkInTime + "weight: " + plWeight);*/
      }
    }
    _weight = 1.0 * plWeight;
    //ai.print(this.ai.obj.name + ": total weight: " + _weight);
    return _weight;
  }

  SystemCheck@ getSystem(Infrastructure& infrastructure) {
    auto@ sysAI = infrastructure.systems.getAI(ai.obj.region);
    if (sysAI !is null) {
      auto@ sys = cast<SystemCheck>(sysAI.bag);
      if (sys !is null)
        return sys;
    }
    return null;
  }

  void build(Infrastructure& infrastructure, Construction& construction, const ConstructionType@ consType, double priority = 1.0, bool force = false, bool critical = false, double delay = 600) {
      ConstructionRequest@ request = infrastructure.planets.requestConstruction(ai, ai.obj, consType, priority, gameTime + delay, BT_Infrastructure);
      PlanetOrder@ order = PlanetOrder(request);
      order.expires = gameTime + delay;
      orders.insertLast(order);
  }
};

final class Infrastructure : AIComponent {
  const ResourceClass@ foodClass, waterClass, scalableClass;

  Development@ development;
  Construction@ construction;
  Orbitals@ orbitals;
	Systems@ systems;
  Planets@ planets;
  Budget@ budget;

  array<SystemCheck@> checkedOwnedSystems;
  array<SystemCheck@> checkedOutsideSystems;
  array<PlanetCheck@> checkedPlanets;

  SystemCheck@ homeSystem;
  NextAction@ nextAction;

  private int _moonBaseStatusId;

  int get_moonBaseStatusId() const {
    return _moonBaseStatusId;
  }

  void create() {
    @development = cast<Development>(ai.development);
    @construction = cast<Construction>(ai.construction);
		@orbitals = cast<Orbitals>(ai.orbitals);
		@systems = cast<Systems>(ai.systems);
    @planets = cast<Planets>(ai.planets);
    @budget = cast<Budget>(ai.budget);

    //Cache expensive lookups
    @foodClass = getResourceClass("Food");
		@waterClass = getResourceClass("WaterType");
		@scalableClass = getResourceClass("Scalable");
		_moonBaseStatusId = getStatusID("MoonBase");

    systems.registerOwnedSystemEvents(OwnedSystemEvents(this));
    systems.registerOutsideBorderSystemEvents(OutsideBorderSystemEvents(this));
    planets.registerPlanetEvents(PlanetEvents(this));
	}

  void save(SaveFile& file) {
    uint cnt = checkedOwnedSystems.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			checkedOwnedSystems[i].save(this, file);
    cnt = checkedOutsideSystems.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			checkedOutsideSystems[i].save(this, file);
    cnt = checkedPlanets.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			checkedPlanets[i].save(this, file);
  }

  void load(SaveFile& file) {
    uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
      SystemCheck@ sys = SystemCheck();
			sys.load(this, file);
      checkedOwnedSystems.insertLast(sys);
		}
    cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
      SystemCheck@ sys = SystemCheck();
			sys.load(this, file);
      checkedOutsideSystems.insertLast(sys);
		}
    cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
      PlanetCheck@ pl = PlanetCheck();
			pl.load(this, file);
      checkedPlanets.insertLast(pl);
		}
  }

  void start() {
  }

  void tick(double time) override {
    SystemCheck@ sys;
    PlanetCheck@ pl;
    //Perform routine duties
    for (uint i = 0, cnt = checkedOwnedSystems.length; i < cnt; ++i) {
      @sys = checkedOwnedSystems[i];
      sys.tick(ai, this, time);
    }
    for (uint i = 0, cnt = checkedOutsideSystems.length; i < cnt; ++i) {
      @sys = checkedOutsideSystems[i];
      sys.tick(ai, this, time);
    }
    for (uint i = 0, cnt = checkedPlanets.length; i < cnt; ++i) {
      @pl = checkedPlanets[i];
      pl.tick(ai, this, time);
    }
  }

  void focusTick(double time) override {
    SystemCheck@ sys;
    PlanetCheck@ pl;

    bool critical = false;
    double w;
    double bestWeight = 0.0;

    //Check if owned systems need anything
    for (uint i = 0, cnt = checkedOwnedSystems.length; i < cnt; ++i) {
      @sys = checkedOwnedSystems[i];
      //Only consider anything if no critical action is underway
      if (!critical) {
        //Evaluate current weight
        w = sys.check(ai);
        if (w > bestWeight)
          bestWeight = w;
        //Check if an outpost is needed
        SystemBuildLocation loc;
        if (shouldHaveOutpost(sys, SA_Core, loc)) {
          @nextAction = SystemAction(sys, BA_BuildOutpost, loc);
          if (log)
            ai.print("outpost considered for owned system with weight: " + w, sys.ai.obj);
        }
      }
      //Perform routine duties
      sys.focusTick(ai, this, time);
    }
    //Check if systems in tradable area need anything
    for (uint i = 0, cnt = checkedOutsideSystems.length; i < cnt; ++i) {
      @sys = checkedOutsideSystems[i];
      //Only consider anything if no critical action is underway
      if (!critical) {
        //Evaluate current weight
        w = sys.check(ai);
        if (w > bestWeight)
          bestWeight = w;
        //Check if an outpost is needed
        SystemBuildLocation loc;
        if (shouldHaveOutpost(sys, SA_Tradable, loc)) {
          @nextAction = SystemAction(sys, BA_BuildOutpost, loc);
          if (log)
            ai.print("outpost considered for outside system with weight: " + w, sys.ai.obj);
        }
      }
      //Perform routine duties
      sys.focusTick(ai, this, time);
    }
    //Check if owned planets need anything
    for (uint i = 0, cnt = checkedPlanets.length; i < cnt; ++i) {
      @pl = checkedPlanets[i];
      //Only consider anything if no critical action is underway
      if (!critical) {
        //Planets are their own 'factory' and can only build one construction at a time
        if (!pl.isBuilding) {
          //Evaluate current weight
          w = pl.check(ai, this);
          if (w > bestWeight)
            bestWeight = w;
          //Check if a moon base is needed
          if (shouldHaveMoonBase(pl)) {
            @nextAction = PlanetAction(pl, BA_BuildMoonBase);
            if (log)
              ai.print("moon base considered with weight: " + w, pl.ai.obj);
            if (pl.isGasGiant && pl.ai.obj.getStatusStackCountAny(moonBaseStatusId) == 0) {
              //The first moon base on gas giants must be built as soon as possible
              nextAction.priority = 2.0;
              critical = true;
            }
          }
        }
      }
      //Perform routine duties
      pl.focusTick(ai, this, time);
    }
    //Execute our next action if there is one
    if (nextAction !is null) {
      Object@ obj;
      auto@ next = cast<SystemAction>(nextAction);
      if (next !is null)
      {
        @sys = next.sys;
        switch (next.action) {
          case BA_BuildOutpost:
            switch (next.loc) {
              case BL_InSystem:
                sys.buildInSystem(this, construction, ai.defs.TradeOutpost, next.priority, next.force);
                break;
              case BL_AtSystemEdge:
                sys.buildAtSystemEdge(this, construction, ai.defs.TradeOutpost, next.priority, next.force);
                break;
              case BL_AtBestPlanet:
                  @obj = getBestPlanet(sys);
                  if (obj !is null) {
                    sys.buildAtPlanet(this, construction, cast<Planet>(obj), ai.defs.TradeOutpost, next.priority, next.force);
                  }
                break;
              default:
                ai.print("ERROR: undefined infrastructure building location for outpost");
            }
            if (log)
              ai.print("outpost ordered", sys.ai.obj);
            break;
          default:
            ai.print("ERROR: undefined infrastructure building action for system");
        }
      }
      else {
        auto@ next = cast<PlanetAction>(nextAction);
        if (next !is null) {
          @pl = next.pl;
          switch (next.action) {
            case BA_BuildMoonBase:
              pl.build(this, construction, ai.defs.MoonBase, next.priority, next.force, next.critical);
              if (log)
                ai.print("moon base ordered", pl.ai.obj);
              break;
            default:
              ai.print("ERROR: undefined infrastructure building action for planet");
          }
        }
      }

      @nextAction = null;
    }
  }

  void registerOwnedSystemAdded(SystemAI& sysAI) {
    auto@ sys = SystemCheck(this, sysAI);
    if (log)
      ai.print("adding owned system: " + sysAI.obj.name);
    checkedOwnedSystems.insertLast(sys);
    @sysAI.bag = sys;
  }

  void registerOwnedSystemRemoved(SystemAI& sysAI) {
    auto@ sys = cast<SystemCheck>(sysAI.bag);
    if (sys !is null) {
      if (log)
        ai.print("removing owned system: " + sysAI.obj.name);
      checkedOwnedSystems.remove(sys);
    }
  }

  void registerOutsideBorderSystemAdded(SystemAI& sysAI) {
    auto@ sys = SystemCheck(this, sysAI);
    if (log)
      ai.print("adding outside system: " + sysAI.obj.name);
    checkedOutsideSystems.insertLast(sys);
    @sysAI.bag = sys;
  }

  void registerOutsideBorderSystemRemoved(SystemAI& sysAI) {
    auto@ sys = cast<SystemCheck>(sysAI.bag);
    if (sys !is null) {
      if (log)
        ai.print("removing outside system: " + sysAI.obj.name);
      checkedOutsideSystems.remove(sys);
    }
  }

  void registerPlanetAdded(PlanetAI& plAI) {
    auto@ pl = PlanetCheck(this, plAI);
    if (log)
      ai.print("adding planet: " + plAI.obj.name);
    checkedPlanets.insertLast(pl);
    @plAI.bag = pl;
  }

  void registerPlanetRemoved(PlanetAI& plAI) {
    auto@ pl = cast<PlanetCheck>(plAI.bag);
    if (pl !is null) {
      if (log)
        ai.print("removing planet: " + plAI.obj.name);
      checkedPlanets.remove(pl);
    }
  }

  bool shouldHaveOutpost(SystemCheck& sys, SystemArea area, SystemBuildLocation&out loc) {
    loc = BL_InSystem;

    uint presentMask = sys.ai.seenPresent;
    //Make sure we did not previously built an outpost here
    if (orbitals.haveInSystem(ai.defs.TradeOutpost, sys.ai.obj)) {
      return false;
    }
    //Make sure we are not already building an outpost here
    if (isBuilding(sys, ai.defs.TradeOutpost))
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
    if (sys.ai.obj.isNebula) {
      int flag = identifyNebula(sys.ai.obj);
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

  bool isBuilding(SystemCheck& sys, const OrbitalModule@ module) {
    for (uint i = 0, cnt = sys.orders.length; i < cnt; ++i) {
      auto@ orbital = cast<BuildOrbital>(sys.orders[i].info);
      if (orbital !is null) {
        if (orbital.module is module)
          return true;
      }
    }
    return false;
  }

  bool isBuilding(PlanetCheck& pl, const ConstructionType@ consType) {
    for (uint i = 0, cnt = pl.orders.length; i < cnt; ++i) {
      auto@ construction = cast<ConstructionRequest>(pl.orders[i].info);
      if (construction !is null) {
        if (construction.type is consType)
          return true;
      }
    }
    return false;
  }

  bool shouldHaveMoonBase(PlanetCheck& pl) {
    if (pl.ai.obj.moonCount == 0)
      return false;
		//Gas giants should have a moon base if there is none already built regardless of any other condition
    if (pl.isGasGiant && pl.ai.obj.getStatusStackCountAny(moonBaseStatusId) == 0)
      return true;
    //If the planet is a gas giant and is at least level 1 and short on empty developed tiles, it should have a moon base
		if (pl.isGasGiant && pl.ai.obj.moonCount > pl.ai.obj.getStatusStackCountAny(moonBaseStatusId)
        && pl.ai.obj.resourceLevel > 0 && pl.ai.obj.emptyDevelopedTiles < 9)
			return true;
    //If the planet is at least level 2 and short on empty developed tiles, it should have a moon base
		else if (pl.ai.obj.resourceLevel > 1 && pl.ai.obj.emptyDevelopedTiles < 9)
			return true;
		//The planet has either a scalable or level 3 or 2 resource and is short on empty developed tiles, it should have a moon base
		/*if (type !is null && (type.cls is scalableClass || type.level == 3 || type.level == 2) plAI.obj.emptyDevelopedTiles < 9)
			return true;*/

		return false;
	}

  int identifyNebula(Region@ region) {
    if (region.getSystemFlag(ai.empire, CERULEAN_NEBULA_FLAG)) {
      if (log)
        ai.print("identified a cerulean nebula");
      return CERULEAN_NEBULA_FLAG;
    }
    else if (region.getSystemFlag(ai.empire, ECONOMIC_NEBULA_FLAG)) {
      if (log)
        ai.print("identified an economic nebula");
      return ECONOMIC_NEBULA_FLAG;
    }
    else if (region.getSystemFlag(ai.empire, EMPTY_SPACE_NEBULA_FLAG)) {
      if (log)
        ai.print("identified empty space");
      return EMPTY_SPACE_NEBULA_FLAG;
    }
    else if (region.getSystemFlag(ai.empire, METAPHASIC_NEBULA_FLAG)) {
      if (log)
        ai.print("identified a metaphasic nebula");
      return METAPHASIC_NEBULA_FLAG;
    }
    else if (region.getSystemFlag(ai.empire, METREON_NEBULA_FLAG)) {
      if (log)
        ai.print("identified a metreon nebula");
      return METREON_NEBULA_FLAG;
    }
    else if (region.getSystemFlag(ai.empire, MUTARA_NEBULA_FLAG)) {
      if (log)
        ai.print("identified a mutara nebula");
      return MUTARA_NEBULA_FLAG;
    }
    else if (region.getSystemFlag(ai.empire, RADIOACTIVE_NEBULA_FLAG)) {
      if (log)
        ai.print("identified a radioactive nebula");
      return RADIOACTIVE_NEBULA_FLAG;
    }
    else if (region.getSystemFlag(ai.empire, TACHYON_NEBULA_FLAG)) {
      if (log)
        ai.print("identified a tachyon nebula");
      return TACHYON_NEBULA_FLAG;
    }
    else if (region.getSystemFlag(ai.empire, TYPE_1_NEBULA_FLAG)) {
      if (log)
        ai.print("identified a type 1 nebula");
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

    if (sys.ai.obj is ai.empire.HomeSystem) {
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
