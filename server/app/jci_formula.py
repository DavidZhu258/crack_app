from __future__ import annotations

import math
from typing import Any


UCS_BY_ROCK_TYPE = {
    "serpentineMarble": 80.0,
    "mediumThickMarble": 35.0,
    "ultrabasicRock": 40.0,
    "mixedRock": 25.0,
    "granite": 28.6,
    "biotiteGneiss": 30.0,
}


class JciFormulaCalculator:
    w1 = 0.0454
    w2 = 0.6586
    w3 = 0.2960
    r456 = 4.0
    jr_ja_ratio = 0.33
    jw = 1.0
    ground_stress_coefficient = 0.027

    def canonical_snapshot(self, input_data: dict[str, Any]) -> dict[str, Any]:
        indicator1 = float(input_data["indicator1"])
        indicator2 = float(input_data["indicator2"])
        indicator3 = float(input_data["indicator3"])
        elevation = float(input_data["elevation"])
        ucs_mpa = UCS_BY_ROCK_TYPE[str(input_data["rockType"])]

        r1 = self.calculate_r1(ucs_mpa)
        r2 = self.calculate_r2(indicator3)
        r3 = self.calculate_r3(indicator2)
        rmr = float(r1 + r2 + r3) + self.r456
        rqd_value = self.calculate_rqd_value(indicator3)
        jn = self.calculate_jn(indicator1)
        srf = self.calculate_srf(elevation)
        q_value = (rqd_value / jn) * self.jr_ja_ratio * (self.jw / srf)
        gq = 10 * math.log10(q_value) + 50
        ground_stress_mpa = self.estimate_ground_stress_mpa(elevation)
        s_value = ucs_mpa / ground_stress_mpa
        hs = 15 * math.log10(s_value)
        jci = self.w1 * rmr + self.w2 * gq + self.w3 * hs

        return {
            "input": {
                "indicator1": self._f(indicator1),
                "indicator2": self._f(indicator2),
                "indicator3": self._f(indicator3),
                "elevation": self._f(elevation),
                "ucsMpa": self._f(ucs_mpa),
            },
            "scores": {
                "R1": r1,
                "R2": r2,
                "R3": r3,
                "RMR": self._f(rmr),
                "RQD_value": self._f(rqd_value),
                "Jn": self._f(jn),
                "SRF": self._f(srf),
                "Q": self._f(q_value),
                "gQ": self._f(gq),
                "groundStressMpa": self._f(ground_stress_mpa),
                "S": self._f(s_value),
                "hS": self._f(hs),
                "JCI": self._f(jci),
            },
        }

    def calculate_r1(self, ucs_mpa: float) -> int:
        if ucs_mpa > 180:
            return 10
        if ucs_mpa >= 70:
            return 7
        if ucs_mpa >= 35:
            return 3
        if ucs_mpa >= 25:
            return 2
        if ucs_mpa >= 1:
            return 1
        return 0

    def calculate_r2(self, indicator3: float) -> int:
        if indicator3 >= 1.571:
            return 3
        if indicator3 >= 1.097:
            return 8
        if indicator3 >= 0.659:
            return 10
        if indicator3 >= 0.276:
            return 17
        return 20

    def calculate_r3(self, indicator2: float) -> int:
        if indicator2 <= 30:
            return 3
        if indicator2 <= 50:
            return 8
        if indicator2 <= 110:
            return 10
        if indicator2 <= 200:
            return 17
        return 20

    def calculate_rqd_value(self, indicator3: float) -> float:
        if indicator3 >= 1.571:
            return 0.15
        if indicator3 >= 1.097:
            return 0.4
        if indicator3 >= 0.659:
            return 0.5
        if indicator3 >= 0.276:
            return 0.85
        return 1.0

    def calculate_jn(self, indicator1: float) -> float:
        if indicator1 <= 0.58:
            return 9.0
        if indicator1 <= 0.91:
            return 6.0
        if indicator1 <= 1.18:
            return 4.0
        if indicator1 <= 1.45:
            return 3.0
        if indicator1 <= 1.92:
            return 2.0
        if indicator1 <= 2.76:
            return 1.0
        return 0.5

    def calculate_srf(self, elevation: float) -> float:
        return 7.5 if (1700 - elevation) > 600 else 2.5

    def estimate_ground_stress_mpa(self, elevation: float) -> float:
        overburden = 1700 - elevation
        effective_overburden = overburden if overburden > 0 else 1.0
        return effective_overburden * self.ground_stress_coefficient

    def _f(self, value: float) -> str:
        return f"{value:.6f}"
