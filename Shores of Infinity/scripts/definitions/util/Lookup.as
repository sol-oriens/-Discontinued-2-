//Search for a match in multiple values without a ugly
//if (foo == bar) || (foo == baz) || ..." list
class Lookup {
	int iValue;

	Lookup(int value) {
		iValue = value;
	}

	bool isIn(const int[]& values) {
		for(uint i = 0, cnt = values.length; i < cnt; ++i) {
			if (iValue == values[i])
				return true;
		}
			return false;
	}
};
