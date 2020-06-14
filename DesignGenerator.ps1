param
(
    [String]$FleetsPath="Fleets",
    [String]$PiratesPath="Pirates",
    [String]$TestFleetsPath="TestFleets"
)
$ErrorActionPreference = 'Stop'

$TankFleet = $true # tank fleets choose the smallest weapon (1:Laser)

$HomeLocation = $PWD

Clear-Host

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
$TestFleetsPath = Get-FleetPath $TestFleetsPath

$Excludes = @("Corvette", "Frigate", "Cruiser")

function Get-Data($path)
{
    #Write-Host("About to read <{0}>" -f $path)
    [xml]$readXML = Get-Content -Path $path
    Write-Host("Read <{0}>" -f $path)
    return $readXML
}

$HullsXML = Get-Data (Join-Path -Path $PSScriptRoot -ChildPath "Hulls.xml")
$WeaponsXML = Get-Data (Join-Path -Path $PSScriptRoot -ChildPath "Weapons.xml")
$PartsXML = Get-Data (Join-Path -Path $PSScriptRoot -ChildPath "Parts.xml")
$MyResearchXML = Get-Data (Join-Path -Path $PSScriptRoot -ChildPath "MyResearch.xml")
$PiratesXML = Get-Data (Join-Path -Path $PSScriptRoot -ChildPath "Pirates.xml")
$PresetsXML = Get-Data (Join-Path -Path $PSScriptRoot -ChildPath "Presets.xml")

$sizeLookup = @{}
$sizeLookup['Tiny'] = 0
$sizeLookup['Small'] = 1
$sizeLookup['Medium'] = 2
$sizeLookup['Large'] = 3
$sizeLookup['Heavy'] = 4
function Create-Options([Xml.XmlElement]$elementList)
{
    $output = @(@(), @(), @(), @(), @()) #Tiny,Small,Medium,Large,Heavy?

    foreach ($elementXML in $elementList.ChildNodes)
    {
        $attribute = $elementXML.GetAttribute("Size")
        $indx = $sizeLookup[$attribute]
        $output[$indx] += $elementXML
    }

    return $output
}

function ConvertTo-NumeralBase
{
    <#
    .SYNOPSIS
        Converts a number to any numeral base between 2 and 36.
    
    .DESCRIPTION
        Converts a number to any numeral base between 2 and 36.

    .EXAMPLE
        PS PipeHow:\Blog> ConvertTo-NumeralBase -Number 300 -Base 16
        12C

        Converts the number 300 to hexadecimal (base 16).
    
    .EXAMPLE
        PS PipeHow:\Blog> ConvertTo-NumeralBase -Number 210 -Base 12
        156

        Converts the number 210 to base 12.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(
            Position = 0,
            Mandatory,
            ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [int]$Number,
        [Parameter(
            Position = 1,
            Mandatory,
            ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [ValidateRange(2,36)]
        [int]$Base
    )
    
    $Characters = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    while ($Number -gt 0)
    {
        $Remainder = $Number % $Base
        $CurrentCharacter = $Characters[$Remainder]
        $ResultNumber = "$CurrentCharacter$ResultNumber"
        $Number = ($Number - $Remainder) / $Base
    }

    $ResultNumber
}

$Weapons = Create-Options($WeaponsXML.Weapons)
$Parts = Create-Options($PartsXML.Parts)


$FleetPower = 576# (LCD of 3, 6, 12, 16) = 48.  Pirate Fleet is 540
function Create-Fleet()
{
    $fleet = @{}
    $fleet["Ships"] = @()
    $fleet["NumberShips"] = 0
    return $fleet
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

function Add-Number($fleet, $ship, $numberShips)
{
    for ($i=0; $i -lt $numberShips; $i++)
    {
        $shipClone = Deep-Copy $ship
        $fleet["Ships"] += $shipClone
    }
    $fleet["NumberShips"] += $numberShips

    $fleet["EVD"] = $ship.Evasion
    $fleet["PROT"] = $ship.Armour
    $fleet["HP"] = $ship.HitPoints
    $fleet["Shields"] = $ship.Shields
}

function Add-Power($fleet, $ship, $power)
{
    $leadership = $ship["Leadership"]
    $numberShips = $power / $leadership

    Add-Number $fleet $ship $numberShips
}

function Save-Fleet($fleet, $path)
{
    #$fleetXML = ConvertTo-Xml -As Document -InputObject $fleet
    $filename = Join-Path -Path $path -ChildPath ($fleet["Name"] + ".xml")
    Export-Clixml -Path $filename -InputObject $fleet -Force
    #$fleetXML.Save($filename)
}

function Create-Ship($hullInfo, $paddedValue)
{
    $thisShip = @{}
    $hullXML = $hullInfo["XML"]
    $thisShip["Load"] = $hullXML.Load -as [int]
    $thisShip["Leadership"] = $hullXML.Leadership -as [int]
    $thisShip["HitPoints"] = $hullXML.HitPoints -as [int]
    $thisShip["Shields"] = $hullXML.Shields -as [int]
    $thisShip["Armour"] = $hullXML.Armour -as [int]
    $thisShip["Accuracy"] = $hullXML.Accuracy -as [int]
    $thisShip["Evasion"] = $hullXML.Evasion -as [int]
    $thisShip["Hull"] = $hullXML.Name
    $thisShip["Weapons"] = @()

    $shipName = $hullXML.Abbreviation
    
    #Write-Host("{0} is {1}" -f $i, $paddedValue)
    for ($thingIndex = 0; $thingIndex -lt $hullInfo["NumberChoices"]; $thingIndex++)
    {
        $thisSize = $hullInfo["Sizes"][$thingIndex] -as [int]
        $thisChoice = $paddedValue.SubString($thingIndex,1) -as [int]
        $isWeapon = $thingIndex -lt $hullInfo["NumberWeapons"]
        $choiceList = if ($isWeapon) {$Weapons} else {$Parts}
        $element = $choiceList[$thisSize][$thisChoice]
        $thisShip["Load"] += $element.Load -as [int]
        $shipName += " " + $element.Abbreviation
        if ($isWeapon)
        {
            $thisShip['Weapons'] += $element.Abbreviation
        }
        else
        {
            $thisShip["HitPoints"] += $element.HitPoints -as [int]
            $thisShip["Shields"] += $element.Shields -as [int]
            $thisShip["Armour"] += $element.Armour -as [int]
            $thisShip["Accuracy"] += $element.Accuracy -as [int]
            $thisShip["Evasion"] += $element.Evasion -as [int]
        }
    }
    $thisShip["Name"] = $shipName
    return $thisShip
}

function Apply-Research($ship)
{
    $hulltype = $ship["Hull"]
    foreach ($tech in $MyResearchXML.Research.ChildNodes)
    {
        if ($tech.Affects -eq $hullType)
        {
            if ($tech.Attribute -eq "HitPoints")
            {
                $ship.HitPoints = ($ship.HitPoints -as [double]) * (1 + $tech.Bonus -as [double])
            }
            elseif ($tech.Attribute -eq "Shields")
            {
                $ship.Shields = ($ship.Shields -as [double]) * (1 + $tech.Bonus -as [double])
            }
            elseif ($tech.Attribute -eq "Armour")
            {
                $ship.Armour = ($ship.Armour -as [double]) * (1 + $tech.Bonus -as [double])
            }
            elseif ($tech.Attribute -eq "Evasion")
            {
                $ship.Evasion = ($ship.Evasion -as [double]) + ($tech.Bonus -as [double])
            }
        }
    }
    $ship["Research"] = $true
}

function Create-Hull($hullXML)
{
    $hullInfo = @{}
    $hullInfo["NumberWeapons"] = 0
    $hullInfo["Sizes"] = @()
    $hullInfo["PatternGroups"] = @()
    $hullInfo["WeaponPatternGroups"] = @()
    foreach ($weaponSize in $hullXML.WeaponSlots.ChildNodes)
    {
        $thisAmount = $weaponSize.'#text'
        $hullInfo["NumberWeapons"] += $thisAmount
        for ($i = 0; $i -lt $thisAmount; $i++)
        {
            $hullInfo["Sizes"] += $sizeLookup[$weaponSize.Name]
        }
        $hullInfo["PatternGroups"] += $thisAmount
        $hullInfo["WeaponPatternGroups"] += $true
    }
    $hullInfo["NumberParts"] = 0
    foreach ($partSize in $hullXML.PartSlots.ChildNodes)
    {
        $thisAmount = $partSize.'#text'
        $hullInfo["NumberParts"] += $thisAmount
        for ($i = 0; $i -lt $thisAmount; $i++)
        {
            $hullInfo["Sizes"] += $sizeLookup[$partSize.Name]
        }
        $hullInfo["PatternGroups"] += $thisAmount
        $hullInfo["WeaponPatternGroups"] += $false
    }
    $hullInfo["NumberChoices"] = $hullInfo["NumberWeapons"] + $hullInfo["NumberParts"]
    $hullInfo["NumberPermutations"] = [Math]::Pow(4,$hullInfo["NumberChoices"])
    $hullInfo["XML"] = $hullXML

    return $hullInfo
}

function Calculate-Patterns($hullInfo)
{
    $shipPatterns = @()
    [System.Collections.ArrayList]$hullInfo["PatternPermutations"] = @()
    $totalPermutations = 1
    $currentGroupChoices = @()
    $groupLengths = @()
    for ($pgi = 0; $pgi -lt $hullInfo["PatternGroups"].length; $pgi++)
    {
        $patternGroup = $hullInfo["PatternGroups"][$pgi]
        $isWeaponGroup = $hullInfo["WeaponPatternGroups"][$pgi]
        $permutations = @()
        if ($TankFleet -and $isWeaponGroup)
        {
            $permutations += ("1").PadLeft($patternGroup, "1")
        }
        else 
        {
            $numberPermutations = [Math]::Pow(4, $patternGroup)
            $existingPermutations = @{}
            for ($i=0; $i -lt $numberPermutations; $i++) 
            {
                [string]$valueAsBase4 = if ($i -eq 0) {"0"} else {ConvertTo-NumeralBase -Number $i -Base 4}
                $base4CharArray = $valueAsBase4.ToCharArray()
                $sortedCharArray = ($base4CharArray | sort-object)
                #$sortedValue = new-object String($sortedCharArray, 0, $valueAsBase4.length)
                $sortedValue = [string]::Join("", ($valueAsBase4.ToCharArray() | sort-object))
                $paddedValue = $sortedValue.PadLeft($patternGroup, "0")
                if ($existingPermutations.ContainsKey($paddedValue) -eq $false)
                {
                    $existingPermutations[$paddedValue] = $true
                    $permutations += $paddedValue
                }
            }    
        }
        
        $_ = $hullInfo["PatternPermutations"].Add($permutations)
        $totalPermutations *= $permutations.Length
        $currentGroupChoices += 0
        $groupLengths += $permutations.Length
    }

    
    while ($true)
    {
        $thisPattern = ""
        for ($i = 0; $i -lt $currentGroupChoices.length; $i++)   
        {
            $currentGroupChoice = $currentGroupChoices[$i]
            $thisPattern += $hullInfo["PatternPermutations"][$i][$currentGroupChoice]
        }
        $shipPatterns += $thisPattern
        $carry = $false
        $currentIncrement = 0
        $done = $false
        do {
            if ($currentIncrement -ge $currentGroupChoices.length)
            {
                $done = $true
                $carry = $false
            }
            elseif (++$currentGroupChoices[$currentIncrement] -ge $groupLengths[$currentIncrement])
            {
                $currentGroupChoices[$currentIncrement++] = 0
                $carry = $true
            }
            else {
                $carry = $false
            }
        } while ($carry)
        if ($done)
        {
            break
        }
    }
    $sortedPatterns = $shipPatterns | Sort-Object
    
    $hullInfo["Patterns"] = $sortedPatterns
}

foreach ($hullXML in $HullsXML.Hulls.ChildNodes)
{
    Write-Host("Hull Category <{0}>" -f $hullXML.Name)
    
    $shouldContinue = $false
    foreach ($exclude in $Excludes)
    {
        if ($hullXML.Name -eq $exclude) { 
            $shouldContinue = $true
            break 
        }
    }
    if ($shouldContinue) { continue }
    
    $hullInfo = Create-Hull $hullXML

    Write-Host("->{0} Weapon Slots`r`n->{1} Part Slots`r`n-->{2} Permutations" -f $numberWeapons, $numberParts, $numberPermutations)
    Calculate-Patterns $hullInfo

    foreach ($shipPattern in $hullInfo["Patterns"])
    {
        $thisShip = Create-Ship $hullInfo $shipPattern
        
        if ($thisShip["Load"] -lt 0)
        {
            #Write-Host("Design is invalid, load is {0}" -f $thisShip["Load"])
            continue
        }
        Apply-Research $thisShip
        
        $fleet = Create-Fleet
        Add-Power $fleet $thisShip $FleetPower
        $fleet["Name"] = ("{0} {1}" -f $fleet["NumberShips"], $thisShip["Name"])
        Save-Fleet $fleet $FleetsPath
    }
}

function Find-Hull($hullType)
{
    foreach ($hullXML in $HullsXML.Hulls.ChildNodes)
    {
        if ($hullXML.Name -eq $hullType)
        {
            return $hullXML
        }
    }
    return $null
}

function Create-Presets($xmlFile, $outputPath)
{
    foreach ($pirateFleet in $xmlFile.Pirates.ChildNodes)
    {
        $fleet = Create-Fleet
        $fleet["Name"] = $pirateFleet.Name
        Write-Host("Test Fleet <{0}>" -f $fleet["Name"])

        foreach ($shipClass in $pirateFleet.ChildNodes)
        {
            $hullXML = Find-Hull $shipClass.Hull
            $hullInfo = Create-Hull $hullXML
            $thisShip = Create-Ship $hullInfo $shipClass.Pattern
            #Apply-Research $thisShip
            Add-Number $fleet $thisShip $shipClass.Number
        }

        Save-Fleet $fleet $outputPath
    }
}

Create-Presets $PiratesXML $PiratesPath
Create-Presets $PresetsXML $TestFleetsPath



