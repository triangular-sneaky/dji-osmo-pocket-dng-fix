function Patch-DjiDngOpCodeList3 {
    [CmdletBinding()]
    param (
        [string]$SourcePath,
        [string]$DestinationPath,

        [switch]$Force
    )

    if ($Quiet) {
        $ErrorActionPreference="Stop";
    } else {
        $ErrorActionPreference="Enquire";
    }


    
    if (-not $DestinationPath) {
        $DestinationPath = $SourcePath;
    } else {
        cp $SourcePath $DestinationPath;
        $overwriteOriginal = "-overwrite_original"
    }

    #1. is vertical?
    $orientation = exiftool -Orientation -b -m $SourcePath ;

    Write-Debug "orientation: $orientation";
    if ($orientation -eq 1) { 
         if (-not $Quiet) {
            Write-Host "$SourcePath : horizontal, skipping"
         }
    } else {
        $oclFile = "$SourcePath--ocl3.dat";
        $patchedOclFile = "$SourcePath--ocl3--patched.dat";

        exiftool -OpCodeList3 -m -b $SourcePath | set-content $oclFile -Encoding Byte;

        $ocl = [System.IO.File]::ReadAllBytes($oclFile);
        $bytesB = $ocl[0x1c..0x1f];
        $bytesR = $ocl[0x20..0x23];

        $correctR = (0,0,0xF,0xA0);
        $correctB = (0,0,0xA,0x6c);

        Write-Debug "Extracted B and R from $oclFile";

        # already correct?
        if (-not (Compare-Object $bytesB $correctB) -and -not (Compare-Object $bytesR $correctR)) {
            Write-Info "$SourcePath : orientation=$orientation but OpCodeList3 appears to be correct (fixed already?); skipping";
        }

        $bNotExpected = Compare-Object $bytesB $correctR;
        $rNotExpected = Compare-Object $bytesR $correctB;

        if ($bNotExpected -or $rNotExpected) {
            $msg = "Unexpected OpCodeList3 Bottom and Right. Expeccted wrong values 0xFA0 0xA6C, got:`nBottom: $(format-hex $bytesB)`nRight: $(format-hex $bytesR)";
            if ($Force) {
                Write-Warning "$SourcePath : $msg; proceeding anyway due to -Force";
            } else {
                throw "$SourcePath : $msg";
            }
        }

        $bytesB.CopyTo($ocl, 0x20);
        $bytesR.CopyTo($ocl, 0x1c);
        

        [System.IO.File]::WriteAllBytes($patchedOclFile, $ocl);

        Write-Debug "Patched ocl to $patchedOclFile";



        cmd /c "exiftool -OpCodeList3<=$patchedOclFile -b -m -n $overwriteOriginal $DestinationPath ";
    }
}