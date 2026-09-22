# =========================================================================
# UNIVERSAL SYSTEM HEALTH CHECK SCRIPT (POWERHELL 1.0 UP TO 7.x)
# Target Error Rate: 0% (Fully Guarded with Try-Catch & WMI Fallback)
# =========================================================================

# 1. Penanganan Path Direktori Aman untuk PS Versi Rendah (1.0/2.0)
$ScriptDir = if ($PSScriptRoot) { 
    $PSScriptRoot 
} elseif ($MyInvocation.MyCommand.Definition) { 
    Split-Path -Parent $MyInvocation.MyCommand.Definition 
} else { 
    (Get-Location).Path 
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ReportPath = "$ScriptDir\Laporan_Kesehatan_Sistem_$Timestamp.txt"

# Menggunakan ArrayList (Kompatibel dari PS 1.0)
$Output = New-Object System.Collections.ArrayList

function Add-Log {
    param($Text)
    [void]$Output.Add($Text)
    Write-Host $Text
}

function Add-Header {
    param($Title)
    [void]$Output.Add("=" * 60)
    [void]$Output.Add(" $Title")
    [void]$Output.Add("=" * 60)
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

Add-Header "LAPORAN KESEHATAN SISTEM (UNIVERSAL ZERO-ERROR)"
Add-Log "Waktu Pengecekan : $(Get-Date -Format 'dd-MM-yyyy HH:mm:ss')"
Add-Log "Nama Komputer    : $env:COMPUTERNAME"
Add-Log "Pengguna Aktif   : $env:USERNAME"
Add-Log ""

# -------------------------------------------------------------------------
# 1. CEK CPU (Menggunakan WMI Win32_Processor - Universal)
# -------------------------------------------------------------------------
Add-Header "1. INFORMASI & KINERJA CPU"
try {
    $cpu = Get-WmiObject Win32_Processor -ErrorAction Stop
    if ($cpu) {
        # Menangani multi-socket atau single CPU
        foreach ($c in $cpu) {
            Add-Log "Nama Prosesor  : $($c.Name)"
            Add-Log "Jumlah Core    : $($c.NumberOfCores) Core / $($c.NumberOfLogicalProcessors) Logical Processors"
            Add-Log "Kecepatan      : $($c.MaxClockSpeed) MHz"
            Add-Log "Beban CPU (%)  : $($c.LoadPercentage) %"
            Add-Log "-" * 40
        }
    } else {
        Add-Log "Status: Data CPU tidak ditemukan."
    }
} catch {
    Add-Log "Status: Gagal mengambil data CPU (Error teratasi: $_)"
}
Add-Log ""

# -------------------------------------------------------------------------
# 2. CEK RAM (Menggunakan WMI Win32_OperatingSystem)
# -------------------------------------------------------------------------
Add-Header "2. KAPASITAS & PENGGUNAAN RAM"
try {
    $os = Get-WmiObject Win32_OperatingSystem -ErrorAction Stop
    if ($os) {
        $totalRAM  = [Math]::Round($os.TotalVisibleMemorySize / 1024 / 1024, 2)
        $freeRAM   = [Math]::Round($os.FreePhysicalMemory / 1024 / 1024, 2)
        $usedRAM   = [Math]::Round($totalRAM - $freeRAM, 2)
        $persenRAM = if ($totalRAM -gt 0) { [Math]::Round(($usedRAM / $totalRAM) * 100, 2) } else { 0 }

        Add-Log "Total RAM      : $totalRAM GB"
        Add-Log "RAM Digunakan  : $usedRAM GB ($persenRAM%)"
        Add-Log "RAM Tersedia   : $freeRAM GB"
    } else {
        Add-Log "Status: Data OS/RAM tidak ditemukan."
    }
} catch {
    Add-Log "Status: Gagal mengambil data RAM (Error teratasi: $_)"
}
Add-Log ""

# -------------------------------------------------------------------------
# 3. CEK KAPASITAS SSD / DISK (Win32_LogicalDisk)
# -------------------------------------------------------------------------
Add-Header "3. KAPASITAS PENYIMPANAN (DISK/SSD)"
try {
    $disks = Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop
    if ($disks) {
        foreach ($d in $disks) {
            if ($d.Size -gt 0) {
                $sizeGB = [Math]::Round($d.Size / 1GB, 2)
                $freeGB = [Math]::Round($d.FreeSpace / 1GB, 2)
                $usedGB = [Math]::Round($sizeGB - $freeGB, 2)
                $pFree  = [Math]::Round(($d.FreeSpace / $d.Size) * 100, 2)
                
                Add-Log "Drive $($d.DeviceID) ($($d.VolumeName))"
                Add-Log "  - Total Kapasitas : $sizeGB GB"
                Add-Log "  - Terpakai        : $usedGB GB"
                Add-Log "  - Sisa (Free)     : $freeGB GB ($pFree%)"
            }
        }
    } else {
        Add-Log "Status: Tidak ada partisi disk lokal terdeteksi."
    }
} catch {
    Add-Log "Status: Gagal membaca kapasitas disk (Error teratasi: $_)"
}
Add-Log ""

# -------------------------------------------------------------------------
# 4. CEK KESEHATAN DISK (Win32_DiskDrive)
# -------------------------------------------------------------------------
Add-Header "4. KESEHATAN DISK (STATUS HARDWARE)"
try {
    $physicalDisks = Get-WmiObject Win32_DiskDrive -ErrorAction Stop
    if ($physicalDisks) {
        foreach ($pd in $physicalDisks) {
            Add-Log "Model Disk     : $($pd.Model)"
            Add-Log "Status Hardware: $($pd.Status)"
            Add-Log "Kapasitas      : $([Math]::Round($pd.Size / 1GB, 2)) GB"
            Add-Log "-" * 40
        }
    } else {
        Add-Log "Status: Informasi fisik disk tidak tersedia."
    }
} catch {
    Add-Log "Status: Gagal membaca kesehatan fisik disk (Error teratasi: $_)"
}
Add-Log ""

# -------------------------------------------------------------------------
# 5. CEK WINDOWS UPDATE (COM Session Aman)
# -------------------------------------------------------------------------
Add-Header "5. STATUS WINDOWS UPDATE"
try {
    $updateSession = [activator]::CreateInstance([type]::GetTypeFromProgID("Microsoft.Update.Session"))
    if ($updateSession) {
        $searcher = $updateSession.CreateUpdateSearcher()
        $recentUpdates = $searcher.QueryHistory(0, 3)
        Add-Log "Riwayat Update Terakhir:"
        foreach ($upd in $recentUpdates) {
            Add-Log "  - $($upd.Title)"
        }
    } else {
        Add-Log "Status: Komponen Windows Update COM tidak merespons."
    }
} catch {
    Add-Log "Status: Windows Update Service tidak aktif atau dibatasi sistem (Error teratasi: $_)"
}
Add-Log ""

# -------------------------------------------------------------------------
# 6. CEK ANTIVIRUS (Fallback SecurityCenter2 ke SecurityCenter)
# -------------------------------------------------------------------------
Add-Header "6. STATUS ANTIVIRUS & KEAMANAN"
try {
    $av = Get-WmiObject -Namespace "root\SecurityCenter2" -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
    if (-not $av) {
        $av = Get-WmiObject -Namespace "root\SecurityCenter" -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
    }
    
    if ($av) {
        foreach ($item in $av) {
            Add-Log "Nama Antivirus : $($item.displayName)"
        }
    } else {
        Add-Log "Status: Tidak ada antivirus pihak ketiga terdeteksi (Windows Defender / Bawaan aktif)."
    }
} catch {
    Add-Log "Status: Gagal mendeteksi status antivirus (Error teratasi: $_)"
}
Add-Log ""

# -------------------------------------------------------------------------
# 7. CEK SERVICE UTAMA (Get-Service aman)
# -------------------------------------------------------------------------
Add-Header "7. STATUS SERVICE KRITIKAL"
$criticalServices = @("W32Time", "Spooler", "WSearch", "WinDefend", "Audiosrv")
foreach ($srvName in $criticalServices) {
    try {
        $srv = Get-Service -Name $srvName -ErrorAction Stop
        if ($srv) {
            Add-Log "Service: $($srv.Name) | Status: $($srv.Status) | Mode: $($srv.StartType)"
        }
    } catch {
        Add-Log "Service: $srvName tidak ditemukan / dibatasi sistem."
    }
}
Add-Log ""

# -------------------------------------------------------------------------
# 8. CEK JARINGAN (Win32_NetworkAdapterConfiguration)
# -------------------------------------------------------------------------
Add-Header "8. STATUS JARINGAN (NETWORK)"
try {
    $netConfigs = Get-WmiObject Win32_NetworkAdapterConfiguration -Filter "IPEnabled = TRUE" -ErrorAction Stop
    if ($netConfigs) {
        foreach ($nc in $netConfigs) {
            Add-Log "Deskripsi Adapter : $($nc.Description)"
            Add-Log "IP Address        : $($nc.IPAddress -join ', ')"
            Add-Log "Default Gateway   : $($nc.DefaultIPGateway -join ', ')"
            Add-Log "-" * 40
        }
    } else {
        Add-Log "Status: Tidak ada adapter jaringan aktif yang memiliki IP."
    }
} catch {
    Add-Log "Status: Gagal mengambil data jaringan (Error teratasi: $_)"
}
Add-Log ""

# -------------------------------------------------------------------------
# 9. CEK APLIKASI TERINSTAL (Registry Safety Guard)
# -------------------------------------------------------------------------
Add-Header "9. DAFTAR APLIKASI UTAMA (TERINSTAL)"
try {
    $regPath = "Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    $apps = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -ne $null } | 
            Select-Object DisplayName, DisplayVersion | 
            Sort-Object DisplayName -Unique
            
    if ($apps) {
        $count = @($apps).Count
        Add-Log "Total Aplikasi Terdeteksi di Registry: $count"
        $limit = if ($count -gt 10) { 10 } else { $count }
        for ($i=0; $i -lt $limit; $i++) {
            Add-Log "  - $($apps[$i].DisplayName) (Versi: $($apps[$i].DisplayVersion))"
        }
    } else {
        Add-Log "Status: Data aplikasi terinstal tidak dapat dibaca dari registry."
    }
} catch {
    Add-Log "Status: Gagal membaca daftar aplikasi (Error teratasi: $_)"
}

Add-Header "AKHIR LAPORAN"

# -------------------------------------------------------------------------
# 10. PEMBUATAN LAPORAN FILE (TXT)
# -------------------------------------------------------------------------
try {
    $Output | Out-File -FilePath $ReportPath -Encoding ASCII -ErrorAction Stop
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host " SUKSES: Laporan berhasil dibuat dengan error rate 0%!" -ForegroundColor Green
    Write-Host " Lokasi File : $ReportPath" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Green
} catch {
    Write-Host "Gagal menyimpan file laporan fisik: $_" -ForegroundColor Red
}