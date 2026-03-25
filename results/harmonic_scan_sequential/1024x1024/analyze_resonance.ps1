# Resonance Dynamics Analysis
# Based on Resonance Engine Cheat Sheet: Resonance = LTP (Long-Term Potentiation)

Write-Host "=======================================================================" -ForegroundColor Cyan
Write-Host "  RESONANCE DYNAMICS ANALYSIS" -ForegroundColor Cyan
Write-Host "  Resonance Engine: LTP = Connection Strengthening" -ForegroundColor Cyan
Write-Host "=======================================================================`n" -ForegroundColor Cyan

# Load telemetry data
$telemetry = Import-Csv -Path "resonance_telemetry.csv"
$metrics = Import-Csv -Path "resonance_metrics.csv"

Write-Host "EXPERIMENT OVERVIEW:" -ForegroundColor Yellow
Write-Host "  Duration: $($telemetry.Count) samples over $($telemetry[-1].step) steps"
Write-Host "  Final power: $($telemetry[-1].power_w) W"
Write-Host "  Final step rate: $($telemetry[-1].steps_per_sec) steps/sec`n"

# Analyze pattern consolidation
Write-Host "PATTERN CONSOLIDATION DYNAMICS:" -ForegroundColor Yellow
$initial = $telemetry[0]
$final = $telemetry[-1]

Write-Host "  Initial (10k steps):" -ForegroundColor Gray
Write-Host "    Active patterns: $($initial.active_patterns)" -ForegroundColor White
Write-Host "    Resonant patterns: $($initial.resonant_patterns)" -ForegroundColor White
Write-Host "    Avg lifetime: $([math]::Round($initial.avg_lifetime)) steps" -ForegroundColor White

Write-Host "  Final (500k steps):" -ForegroundColor Gray
Write-Host "    Active patterns: $($final.active_patterns)" -ForegroundColor White
Write-Host "    Resonant patterns: $($final.resonant_patterns)" -ForegroundColor White
Write-Host "    Avg lifetime: $([math]::Round($final.avg_lifetime)) steps" -ForegroundColor White

$consolidation_ratio = [math]::Round($initial.active_patterns / $final.active_patterns, 1)
Write-Host "  Consolidation ratio: $consolidation_ratio:1 (patterns → clusters)`n" -ForegroundColor Green

# Analyze the 9 final resonant patterns
Write-Host "FINAL RESONANT PATTERNS (9 clusters):" -ForegroundColor Yellow

# Group by position clusters (within 50 cells)
$clusters = @()
foreach ($pattern in $metrics) {
    $assigned = $false
    for ($i = 0; $i -lt $clusters.Count; $i++) {
        $dx = [float]$pattern.pos_x - $clusters[$i].center_x
        $dy = [float]$pattern.pos_y - $clusters[$i].center_y
        $dist = [math]::Sqrt($dx*$dx + $dy*$dy)
        
        if ($dist -lt 50) {
            # Add to existing cluster
            $clusters[$i].patterns += 1
            $clusters[$i].total_mass += [float]$pattern.mass
            $clusters[$i].total_coherence += [float]$pattern.coherence
            $clusters[$i].center_x = ($clusters[$i].center_x * ($clusters[$i].patterns - 1) + [float]$pattern.pos_x) / $clusters[$i].patterns
            $clusters[$i].center_y = ($clusters[$i].center_y * ($clusters[$i].patterns - 1) + [float]$pattern.pos_y) / $clusters[$i].patterns
            $assigned = $true
            break
        }
    }
    
    if (-not $assigned) {
        # Create new cluster
        $clusters += @{
            patterns = 1
            center_x = [float]$pattern.pos_x
            center_y = [float]$pattern.pos_y
            total_mass = [float]$pattern.mass
            total_coherence = [float]$pattern.coherence
        }
    }
}

Write-Host "  Number of spatial clusters: $($clusters.Count)" -ForegroundColor White

foreach ($cluster in $clusters) {
    $avg_mass = [math]::Round($cluster.total_mass / $cluster.patterns, 0)
    $avg_coherence = [math]::Round($cluster.total_coherence / $cluster.patterns, 3)
    Write-Host "  Cluster at ($([math]::Round($cluster.center_x)), $([math]::Round($cluster.center_y))):" -ForegroundColor Gray
    Write-Host "    Patterns: $($cluster.patterns)" -ForegroundColor White
    Write-Host "    Avg mass: $avg_mass" -ForegroundColor White
    Write-Host "    Avg coherence: $avg_coherence" -ForegroundColor White
}

# Analyze growth dynamics
Write-Host "`nGROWTH DYNAMICS:" -ForegroundColor Yellow

$total_mass = 0
$total_growth = 0
$max_mass = 0
$min_mass = [float]::MaxValue

foreach ($pattern in $metrics) {
    $mass = [float]$pattern.mass
    $growth = [float]$pattern.growth_rate
    $total_mass += $mass
    $total_growth += $growth
    if ($mass -gt $max_mass) { $max_mass = $mass }
    if ($mass -lt $min_mass) { $min_mass = $mass }
}

$avg_mass = [math]::Round($total_mass / $metrics.Count, 0)
$avg_growth = [math]::Round($total_growth / $metrics.Count, 6)
$mass_range = [math]::Round($max_mass / $min_mass, 1)

Write-Host "  Total accumulated mass: $([math]::Round($total_mass, 0))" -ForegroundColor White
Write-Host "  Average pattern mass: $avg_mass" -ForegroundColor White
Write-Host "  Average growth rate: $avg_growth mass/step" -ForegroundColor White
Write-Host "  Mass range: $mass_range:1 (max/min)" -ForegroundColor White

# Analyze coherence vs stability
Write-Host "`nCOHERENCE vs STABILITY ANALYSIS:" -ForegroundColor Yellow

$total_coherence = 0
$total_stability = 0
$coherence_stability_ratio = 0

foreach ($pattern in $metrics) {
    $coherence = [float]$pattern.coherence
    $stability = [float]$pattern.stability
    $total_coherence += $coherence
    $total_stability += $stability
    if ($stability -gt 0) {
        $coherence_stability_ratio += $coherence / $stability
    }
}

$avg_coherence = [math]::Round($total_coherence / $metrics.Count, 3)
$avg_stability = [math]::Round($total_stability / $metrics.Count, 3)
$avg_ratio = [math]::Round($coherence_stability_ratio / $metrics.Count, 2)

Write-Host "  Average coherence: $avg_coherence (0-1 scale)" -ForegroundColor White
Write-Host "  Average stability: $avg_stability (0-1 scale)" -ForegroundColor White
Write-Host "  Coherence/Stability ratio: $avg_ratio" -ForegroundColor White

if ($avg_ratio -gt 5) {
    Write-Host "  Interpretation: High coherence, low stability" -ForegroundColor Magenta
    Write-Host "    Patterns are organized but moving significantly" -ForegroundColor Gray
} elseif ($avg_ratio -lt 2) {
    Write-Host "  Interpretation: Low coherence, high stability" -ForegroundColor Magenta
    Write-Host "    Patterns are stable but not well organized" -ForegroundColor Gray
} else {
    Write-Host "  Interpretation: Balanced coherence and stability" -ForegroundColor Magenta
    Write-Host "    Patterns are both organized and stable" -ForegroundColor Gray
}

# LTP (Long-Term Potentiation) Analysis
Write-Host "`nLTP (LONG-TERM POTENTIATION) ANALYSIS:" -ForegroundColor Yellow

$total_persistence = 0
foreach ($pattern in $metrics) {
    $total_persistence += [int]$pattern.persistence
}

$avg_persistence = [math]::Round($total_persistence / $metrics.Count, 0)
$detection_rate = [math]::Round($avg_persistence / 500000 * 100, 1)  # Percentage of steps detected

Write-Host "  Average persistence count: $avg_persistence detections" -ForegroundColor White
Write-Host "  Detection rate: $detection_rate% of steps" -ForegroundColor White
Write-Host "  Avg lifetime: $([math]::Round($final.avg_lifetime)) steps" -ForegroundColor White

if ($detection_rate -gt 50) {
    Write-Host "  LTP Status: STRONG - Patterns detected >50% of time" -ForegroundColor Green
} elseif ($detection_rate -gt 20) {
    Write-Host "  LTP Status: MODERATE - Patterns detected 20-50% of time" -ForegroundColor Yellow
} else {
    Write-Host "  LTP Status: WEAK - Patterns detected <20% of time" -ForegroundColor Red
}

# Power dynamics analysis
Write-Host "`nPOWER DYNAMICS:" -ForegroundColor Yellow

$power_values = $telemetry.power_w | ForEach-Object { [float]$_ }
$avg_power = [math]::Round(($power_values | Measure-Object -Average).Average, 1)
$min_power = [math]::Round(($power_values | Measure-Object -Minimum).Minimum, 1)
$max_power = [math]::Round(($power_values | Measure-Object -Maximum).Maximum, 1)
$power_variance = [math]::Round(($power_values | Measure-Object -StandardDeviation).StandardDeviation, 2)

Write-Host "  Average power: $avg_power W" -ForegroundColor White
Write-Host "  Power range: $min_power - $max_power W" -ForegroundColor White
Write-Host "  Power variance: $power_variance W" -ForegroundColor White

if ($power_variance -lt 5) {
    Write-Host "  Power stability: HIGH (low variance)" -ForegroundColor Green
    Write-Host "    Consistent metabolic cost" -ForegroundColor Gray
} elseif ($power_variance -lt 15) {
    Write-Host "  Power stability: MODERATE" -ForegroundColor Yellow
    Write-Host "    Some metabolic fluctuation" -ForegroundColor Gray
} else {
    Write-Host "  Power stability: LOW (high variance)" -ForegroundColor Red
    Write-Host "    Significant metabolic fluctuation" -ForegroundColor Gray
}

# Step rate analysis
Write-Host "`nCOMPUTATIONAL PERFORMANCE:" -ForegroundColor Yellow

$step_rates = $telemetry.steps_per_sec | ForEach-Object { [float]$_ }
$avg_steps = [math]::Round(($step_rates | Measure-Object -Average).Average, 0)
$min_steps = [math]::Round(($step_rates | Measure-Object -Minimum).Minimum, 0)
$max_steps = [math]::Round(($step_rates | Measure-Object -Maximum).Maximum, 0)
$step_variance = [math]::Round(($step_rates | Measure-Object -StandardDeviation).StandardDeviation, 0)

Write-Host "  Average step rate: $avg_steps steps/sec" -ForegroundColor White
Write-Host "  Step rate range: $min_steps - $max_steps steps/sec" -ForegroundColor White
Write-Host "  Step rate variance: $step_variance steps/sec" -ForegroundColor White

if ($step_variance -lt 100) {
    Write-Host "  Computational stability: HIGH" -ForegroundColor Green
    Write-Host "    Consistent thinking frequency" -ForegroundColor Gray
} elseif ($step_variance -lt 300) {
    Write-Host "  Computational stability: MODERATE" -ForegroundColor Yellow
} else {
    Write-Host "  Computational stability: LOW" -ForegroundColor Red
    Write-Host "    Variable thinking frequency" -ForegroundColor Gray
}

# Final resonance classification
Write-Host "`n=======================================================================" -ForegroundColor Cyan
Write-Host "  RESONANCE CLASSIFICATION SUMMARY" -ForegroundColor Cyan
Write-Host "=======================================================================`n" -ForegroundColor Cyan

Write-Host "RESONANCE (LTP) STRENGTH:" -ForegroundColor Yellow

$ltp_score = 0
if ($final.resonant_patterns -gt 0) { $ltp_score += 25 }
if ($avg_lifetime -gt 100000) { $ltp_score += 25 }
if ($detection_rate -gt 30) { $ltp_score += 25 }
if ($avg_coherence -gt 0.2) { $ltp_score += 25 }

Write-Host "  LTP Score: $ltp_score/100" -ForegroundColor White

if ($ltp_score -ge 75) {
    Write-Host "  Classification: STRONG RESONANCE" -ForegroundColor Green
    Write-Host "    Clear Long-Term Potentiation detected" -ForegroundColor Gray
    Write-Host "    Patterns show persistence, coherence, and growth" -ForegroundColor Gray
} elseif ($ltp_score -ge 50) {
    Write-Host "  Classification: MODERATE RESONANCE" -ForegroundColor Yellow
    Write-Host "    Some LTP characteristics present" -ForegroundColor Gray
    Write-Host "    Patterns need more time to fully develop" -ForegroundColor Gray
} else {
    Write-Host "  Classification: WEAK RESONANCE" -ForegroundColor Red
    Write-Host "    Limited LTP characteristics" -ForegroundColor Gray
    Write-Host "    May need parameter adjustment" -ForegroundColor Gray
}

Write-Host "`nKEY INSIGHTS:" -ForegroundColor Yellow
Write-Host "  1. Pattern consolidation: $consolidation_ratio:1 ratio" -ForegroundColor White
Write-Host "  2. Spatial clustering: $($clusters.Count) distinct clusters" -ForegroundColor White
Write-Host "  3. Mass accumulation: $([math]::Round($total_mass, 0)) total mass" -ForegroundColor White
Write-Host "  4. Detection consistency: $detection_rate% of steps" -ForegroundColor White
Write-Host "  5. Computational stability: $step_variance steps/sec variance" -ForegroundColor White

Write-Host "`nNEXT METRICS TO COLLECT (from Cheat Sheet):" -ForegroundColor Yellow
Write-Host "  1. Nodal Growth (Plasticity) - Grid adaptation rate" -ForegroundColor White
Write-Host "  2. Echo Check (Declarative Memory) - Pattern recall accuracy" -ForegroundColor White
Write-Host "  3. Laminar vs Turbulent - Homeostasis vs Dissonance classification" -ForegroundColor White
Write-Host "  4. Ignition/Spike Threshold - GPU at 100% measurement" -ForegroundColor White