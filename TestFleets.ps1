param
(
    [String]$FleetsPath="Fleets",
    [String]$PiratesPath="Pirates",
    [String]$PresetPath="TestFleets",
    [String]$OutputFile="Frigates.csv"
)
$ErrorActionPreference = 'Stop'

$TestFleetFireBack = $true

$HomeLocation = $PWD

Clear-Host

function Chance-ToHit1($ar, $evd)
{
    $evasion = $evd
    $activeAccuracy = $ar - $evasion
    if ($activeAccuracy -gt 100) { $activeAccuracy = 100; }
    
    $hitPercentage = $activeAccuracy / 100.0
    return $hitPercentage
}

function Chance-ToHit2($ar, $evd)
{
    $hitPercentage = $ar / ($ar + $evd)
    return $hitPercentage
}

function Chance-ToHit($ar, $evd)
{
    return Chance-ToHit2 $ar $evd
}

function Get-Data($path)
{
    #Write-Host("About to read <{0}>" -f $path)
    [xml]$readXML = Get-Content -Path $path
    Write-Host("Read <{0}>" -f $path)
    return $readXML
}

$WeaponsXML = Get-Data (Join-Path -Path $PSScriptRoot -ChildPath "Weapons.xml")
$MyResearchXML = Get-Data (Join-Path -Path $PSScriptRoot -ChildPath "MyResearch.xml")

function Get-FleetPath($path)
{
    $path = Join-Path -Path $PSScriptRoot -ChildPath $path
    If(!(Test-Path $path))
    {
        New-Item -ItemType Directory -Force -Path $path
    }
    return $path
}

$FleetsPath = Get-FleetPath $FleetsPath
$PiratesPath = Get-FleetPath $PiratesPath
$PresetPath = Get-FleetPath $PresetPath
function Get-Data($path)
{
    #Write-Host("About to read <{0}>" -f $path)
    [xml]$readXML = Get-Content -Path $path
    Write-Host("Read <{0}>" -f $path)
    return $readXML
}

function Valid-Target($ship)
{
    return $ship["HitPoints"] -gt 0
    #return $ship.Alive
}

function Choose-Target($origin, $fleet)
{
    $minTargeted = [int32]::MaxValue
    $validTarget = $false
    $numberValidTargets = 0
    if ($origin["Target"] -ne $null)
    {
        $ship = $fleet[$origin["Target"]]
        if (Valid-Target $ship)
        {
            $ship["Targeted"]++;
            return $ship
        } 
    }
    foreach ($ship in $fleet)
    {
        if (Valid-Target $ship)# -or $ship["HitPoints"] -gt 0)
        {
            $targeted = $ship["Targeted"]
            $minTargeted = [Math]::Min($minTargeted, $targeted)
            $validTarget = $true
            $numberValidTargets++
        }
    }
    if ($validTarget -eq $false)
    {
        return $null
    }
    $targetIndex = (Get-Random) % $numberValidTargets
    $testIndex = 0

    for ($i = 0; $i -lt $fleet.Count; $i++)
    #foreach ($ship in $fleet)
    {
        $ship = $fleet[$i]
        if ((Valid-Target $ship) -and $testIndex++ -eq $targetIndex)
        {
            $ship["Targeted"]++;
            $origin["Target"] = $i
            return $ship
        }
    }
}

function Get-Weapon($abbreviation)
{
    foreach($weapon in $WeaponsXML.Weapons.ChildNodes)
    {
        if ($weapon.Abbreviation -eq $abbreviation)
        {
            return $weapon
        }
    }
    return $null
}

function Modify-Weapon($weapon)
{
    $weaponType = $weapon.Name
    $weapon.SetAttribute("DamageMultiplier", "1")
    foreach ($tech in $MyResearchXML.Research.ChildNodes)
    {
        if ($tech.Affects -eq "Fleet" -or $tech.Affects -eq $weaponType)
        {
            if ($tech.Attribute -eq "Damage")
            {
                $weapon.DamageMultiplier = ($weapon.DamageMultiplier -as [double]) + ($tech.Bonus -as [double])
            }
            elseif ($tech.Attribute -eq "Accuracy")
            {
                $weapon.Accuracy = ($weapon.Accuracy -as [double]) + ($tech.Bonus -as [double])
            }
        }
    }
    return $weapon
}

$lostOnShields = 0.5

function Open-Fire($shipA, $shipB, $round)
{
    foreach ($weaponName in $shipA["Weapons"])
    {
        #Write-Host("Weapon <{0}> Firing" -f $weaponName)
        $weapon = Get-Weapon $weaponName
        $roundModulo = $round % ($weapon.AttackSpeed -as [int])
        if ($roundModulo -eq 0)
        {
            $activeWeapon = $weapon.Clone()
            if ($shipA.Research)
            {
                $activeWeapon = Modify-Weapon $activeWeapon
            }
            $baseDamage = ($activeWeapon.Damage -as [double]) * ($activeWeapon.DamageMultiplier -as [double])

            $accuracy = ($activeWeapon.Accuracy -as [double]) + ($shipA.Accuracy -as [double])
            $evasion = $shipB.Evasion
            $hitPercentage = Chance-ToHit $accuracy $evasion

            $shipB["Damage"] += $baseDamage

            [double]$randomRoll = Get-Random -Minimum 0.0 -Maximum 1.0 
            if ($randomRoll -le $hitPercentage)
            {
                #Write-Host("Damage <{0}>" -f $accuracy)
                #Write-Host("Accuracy <{0}> vs <{1}> = <{2}%>" -f $accuracy, $evasion, $activeAccuracy)

                $damageHit = $baseDamage
                #Write-Host("Hit <{0}> Damage" -f $damageHit)

                $damageDeflected = 0
                $damageLost = 0
                if ($shipB.Shields -gt 0)
                {
                    $damageDeflected = [Math]::Min(((100.0 - $weapon.ShieldPiercing) / 100.0) * $damageHit, $shipB.Shields -as [double])
                    
                    $shipB.Shields -= $damageDeflected
                    $shipB["DamageDeflected"] += $damageDeflected
                    $damageLost = ($damageHit - $damageDeflected) * $lostOnShields;
                }
                
                $damagePastShields = $damageHit - $damageDeflected - $damageLost
                
                $damageAbsorbed = 0
                if ($shipB.Armour -gt 0)
                {
                    $damageAbsorbed = ((100 - $weapon.ArmourPiercing) / 100.0) * $shipB.Armour
                }

                $damagePastArmour = $damagePastShields - $damageAbsorbed
                
                $damageReduced = 0
                foreach ($hullModifier in $weapon.HullModifiers.ChildNodes)
                {
                    if ($hullModifier.Name -eq $shipB.Hull)
                    {
                        $modifier = $hullModifier.'#text' -as [double]
                        $damageReduced = $damagePastArmour * (1.0 - $modifier)
                    }
                }
                $damageToHull = [Math]::Min($shipB.HitPoints, $damagePastArmour - $damageReduced)
                $shipB.HitPoints -= $damageToHull
                
                $shipB["Hit"] += $damageHit
                $shipB["Pierced"] += $damagePastShields
                $shipB["Penetrated"] += $damagePastArmour
                $shipB["Received"] += $damageToHull
            }
                
            
        }
    }
    if ($shipB.HitPoints -le 0)
    {
        return $true
    }
    return $false
}

function Reset-Targeting($fleet)
{
    foreach ($ship in $fleet["Ships"])
    {
        $ship["Targeted"] = 0
        $ship["Alive"] = ($ship.HitPoints -gt 0)
    }
}

function Fleet-Fire($fleetA, $fleetB)
{
    # each ship in each fleet fires all weapons at a single target (if not killed already this round)
    foreach ($ship in $fleetA["Ships"])
    {
        if ($ship.Alive)
        {
            $target = Choose-Target $ship $fleetB["Ships"]
            if ($target -ne $null)
            {
                $disabled = Open-Fire $ship $target $round
                if ($disabled)
                {
                    $fleetB.NumberShips -= 1
                }
            }
            else
            {
                break
            }
        }
    }
}

function Initialise-Damage($fleet)
{
    foreach ($ship in $fleet["Ships"])
    {
        $ship["OriginalHP"] = $ship["HitPoints"]
        $ship["OriginalShields"] = $ship["Shields"]
        $ship["Damage"] = 0
        $ship["Hit"] = 0
        $ship["Pierced"] = 0
        $ship["DamageDeflected"] = 0
        $ship["Penetrated"] = 0
        $ship["Received"] = 0
    }
    $fleet["OriginalShips"] = $fleet["NumberShips"]
}

function Collate-Damage($fleet)
{
    $shipHP = $fleet["HP"]
    $shipShields = $fleetA["Shields"]
    $originalShips = $fleet["OriginalShips"]
    
    $fleet["Damage"] = 0
    $fleet["Hit"] = 0
    $fleet["Pierced"] = 0
    $fleet["Penetrated"] = 0
    $fleet["Received"] = 0
    $totalShieldLoss = 0
    $totalHPLoss = 0
    $totalHP = 0
    $totalShields = 0
    
    foreach ($ship in $fleet["Ships"])
    {
        $fleet["Damage"] += $ship["Damage"]
        $fleet["Hit"] += $ship["Hit"]
        $fleet["Pierced"] += $ship["Pierced"]
        $fleet["Penetrated"] += $ship["Penetrated"]
        $fleet["Received"] += $ship["Received"]

        $totalHP += $ship["OriginalHP"]
        $totalShields += $ship["OriginalShields"]

        $totalShieldLoss += $ship["DamageDeflected"]
        $totalHPLoss += $ship["Received"]
    }
    $totalHealth = $totalHP + $totalShields

    $fleet["TotalHPLoss"] = $totalHPLoss -as [int]
    $fleet["TotalShieldLoss"] = $totalShieldLoss -as [int]
    $fleet["TotalLoss"] = ($totalHPLoss + $totalShieldLoss) -as [int]
    $fleet["TotalLossPC"] = [math]::round(($totalHPLoss / $totalHP) * 100.0, 2)#($totalHPLoss + $totalShieldLoss) / $totalHealth

    $fleet["Damage"] /= $totalHealth
    $fleet["Hit"] /= $totalHealth
    $fleet["Pierced"] /= $totalHealth
    $fleet["Penetrated"] /= $totalHealth
    $fleet["Received"] /= $totalHealth
}

function Smash-Fleets($fleetA, $fleetB)
{
    Initialise-Damage $fleetA
    Initialise-Damage $fleetB
    $round = 0
    while ($true)
    {
        $round++;
        
        Reset-Targeting $fleetA
        Reset-Targeting $fleetB

        Fleet-Fire $fleetA $fleetB
        Fleet-Fire $fleetB $fleetA        
        
        if ($fleetA["NumberShips"] -le 0 -or $fleetB["NumberShips"] -le 0)# -or $round -ge 12)
        {
            Collate-Damage $fleetA
            Collate-Damage $fleetB
            Write-Host("{0} {1}({2}) vs {3} {4}({5}): Round {6}" -f $fleetA["Name"], -$fleetA["TotalLoss"], $fleetA["TotalLossPC"], $fleetB["Name"], -$fleetB["TotalLoss"], $fleetB["TotalLossPC"], $round)
            $damageInfo = ("{0}, {1}, {2}, {3}, {4}, {5}" -f $fleetA["Name"], $fleetA["Damage"], $fleetA["Hit"], $fleetA["Pierced"], $fleetA["Penetrated"], $fleetA["Received"])
            #Write-Host $damageInfo
            Add-Content -Path $OutputFile -Value $damageInfo
            break
        }
    }
}

$PirateFleets = @()

Get-ChildItem $PiratesPath -Filter *.xml | 
Foreach-Object {
    $fleet = Import-Clixml -Path $_.FullName
    $PirateFleets += $fleet
}

$PresetFleets = @()

Get-ChildItem $PresetPath -Filter *.xml | 
Foreach-Object {
    $fleet = Import-Clixml -Path $_.FullName
    $PresetFleets += $fleet
}

function Deep-Copy($obj)
{
    $ms = New-Object System.IO.MemoryStream
    $bf = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
    $bf.Serialize($ms, $obj)
    $ms.Position = 0
    $ret = $bf.Deserialize($ms)
    $ms.Close()
    return $ret
}

$header = "ShipName, Damage, Hit, Pierced, Penetrated, Received"

Set-Content -Path $OutputFile -Value $header

function TestAll()
{
    Get-ChildItem $FleetsPath -Filter *.xml | 
    Foreach-Object {
        $testFleet = Import-Clixml -Path $_.FullName
        foreach($pirateFleet in $PirateFleets)
        {
            $fleetA = $testFleet
            $fleetB = Deep-Copy $pirateFleet
            Smash-Fleets $fleetA $fleetB
        }
    }
}

function Test-Presets()
{
    foreach($presetFleet in $PresetFleets)
    {
        foreach($private:pirateFleet in $PirateFleets)
        {
            $fleetA = Deep-Copy $presetFleet
            $fleetB = Deep-Copy $private:pirateFleet
            Smash-Fleets $fleetA $fleetB
        }
    }
}

Test-Presets
