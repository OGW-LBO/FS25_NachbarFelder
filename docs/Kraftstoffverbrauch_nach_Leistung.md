# Leistungsabhängiger Kraftstoffverbrauch (Konzept nach MoreRealistic)

## Ziel
Der Verbrauch folgt der tatsächlich erzeugten Motorleistung in kW, also wie stark das Fahrzeug arbeitet. Die Drehzahl fließt nur gering ein.

## Wo eingegriffen wird
Die Klasse `Motorized` hat die Funktion `updateConsumers(dt, accInput)`. Sie zieht pro Frame den Kraftstoff aus dem Tank ab. MoreRealistic überschreibt sie in `scripts/MR_Motorized.lua` (`Motorized.mrUpdateConsumers`, ca. Zeilen 63–150). Der Einstieg in der eigenen Mod:

```lua
Motorized.updateConsumers = Utils.overwrittenFunction(Motorized.updateConsumers, MyMod.updateConsumers)
```

## Formel
```
Leistung_aktuell = Drehmoment [Nm] * Drehzahl [rpm] / 9.55      -> Watt
loadFactor       = Leistung_aktuell / Nennleistung               (0..1)
rpmFactor        = aktuelle Drehzahl / Drehzahl bei Nennleistung
efficiencyFx     = 1 im Bereich 75 % bis 100 % der Nenndrehzahl;
                   darunter oder darüber steigt der Verbrauch (Wirkungsgrad)
motorFactor      = min((0.1*rpmFactor + 0.9*loadFactor) * efficiencyFx, 1.25)
Verbrauch/Frame  = usageFactor * motorFactor * consumer.usage * dt
```

Werte bei MoreRealistic:
- Wirkungsgrad: unterhalb von 75 % der Nenndrehzahl ca. +10 % Verbrauch je 600 rpm weniger. Oberhalb der Nenndrehzahl ca. +15 % je 300 rpm mehr.
- Gewichtung: 90 % Last, 10 % Drehzahl.
- `usageFactor`: 0.5 / 1 / 2.5 je nach Spieleinstellung (niedrig, mittel, hoch), zusätzlich ×0.5 für Vanilla-Fahrzeuge, weil die Vanilla-XML-Werte laut Autor etwa doppelt so hoch wie in der Realität sind.
- Schaden am Fahrzeug erhöht den Verbrauch (`Motorized.DAMAGED_USAGE_INCREASE`).
- Obergrenze 1.25 als Schutz vor Ausreißern.

## Was von der Originalfunktion bleibt
Die Schleife über `spec.consumers` aus der Vanilla-Funktion übernehmen:
- Ansammeln in `consumer.fillLevelToChange`, Abbuchen erst ab 1 Liter.
- Statistik `updateFarmStats(..., "fuelUsage", ...)`.
- Helfer-Kosten bei `helperBuyFuel`.
- Anzeige `spec.lastFuelUsage` (l/h).

Ändern müssen nur `motorFactor` und `usageFactor`.

## Vor dem Einbau prüfen
1. **Feldnamen:** MR nutzt `motor.peakMotorPower`, `motor.peakMotorPowerRotSpeed`, `motor.motorAppliedTorque`, `motor.lastMotorRpm`, `motor.motorRotSpeed`. Nicht sicher, dass alle in Vanilla existieren. `peakMotorPower` und `peakMotorPowerRotSpeed` stammen möglicherweise aus MR. Nennleistung ggf. aus der Drehmomentkurve (`motor:getTorqueCurve()`) selbst bestimmen. Nicht gegen die FS25-API geprüft.
2. **Kalibrierung:** Skalierung gegen die Verbrauchswerte der Vanilla-XML (`consumer.usage`) prüfen.
3. **Gerätelast:** Der Verbrauch folgt der Motorlast. Wie realistisch das ist, hängt vom Zugkraftbedarf der Geräte ab. MR passt ihn separat an (`MR_PowerConsumer.lua`).
4. **Konflikte:** Andere Mods, die `updateConsumers` überschreiben (z. B. MoreRealistic), kollidieren. Mit `overwrittenFunction` laufen beide Mods hintereinander.
5. **Lizenz:** Der MR-Code gehört Dural. Die Funktion selbst nach dieser Formel schreiben, nicht den Code kopieren.
