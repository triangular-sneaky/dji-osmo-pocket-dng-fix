function GetInt32BigEndian {
    param (
        [byte[]]$bytes,
        [int]$index
    )

    $v = $bytes[$index..($index+3)];
    [Array]::Reverse($v);
    #Write-Debug "GetInt32BigEndian: Reversed: $($v | format-hex) "
    return [System.BitConverter]::ToInt32($v, 0);
}

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
        $oclFile = "$(resolve-path $SourcePath)--ocl3.dat";
        $patchedOclFile =  "$(resolve-path $SourcePath)--ocl3--patched.dat";

        
        start-process exiftool "-OpCodeList3 -m -b $SourcePath" -RedirectStandardOutput $oclFile -Wait -NoNewWindow -WorkingDirectory $pwd;
        
        #Write-Debug " v";


        $ocl = [System.IO.File]::ReadAllBytes($oclFile);

        # parse ocl
        $count = GetInt32BigEndian $ocl 0;
        Write-Debug "Opcodes count: $count";

        $offset = 4;
        for ($i = 0; $i -lt $count; $i++) {
            $ocid = GetInt32BigEndian $ocl $offset
            Write-Debug "OCID $ocid @ $offset";
            if ($ocid -eq 9) { #gainmap
                $gainMapOffset = $offset;
                Write-Debug "Found GainMap at offset $offset";
                break;
            }

            $variableSize = GetInt32BigEndian $ocl ($offset + 12);
            Write-Debug "variableSize $variableSize @ $($offset + 12)";
            $offset = $offset + 4*4 + $variableSize;
        }

        if (-not $gainMapOffset) {
            throw "Couldnt find GainMap opcode in OpCodeList3"
        }

        $bytesBOffset = ($gainMapOffset + 0x18);
        $bytesROffset = ($gainMapOffset + 0x1C);
        $bytesB = $ocl[$bytesBOffset..($bytesBOffset + 3)];
        $bytesR = $ocl[$bytesROffset..($bytesROffset + 3)];
        $b = GetInt32BigEndian $bytesB 0;
        $r = GetInt32BigEndian $bytesR 0;


        $correctR = 0xFA0;
        $correctB = 0xA6c;

        Write-Debug "Extracted B and R from $oclFile";

        # already correct?
        if ((($b -eq $correctB) -or ($r  -eq $correctR)) -and ($b -lt $r)) {
            Write-Host ("$SourcePath : orientation=$orientation but OpCodeList3 appears to be correct (fixed already?) Bottom {0:x} is less than Right {1:x}; skipping" -f $b,$r);
            return;
        }

        $bNotExpected = $b -ne $correctR;
        $rNotExpected = $r -ne $correctB;

        if ($bNotExpected -and $rNotExpected) {
            $msg = "Totally unexpected OpCodeList3 Bottom and Right. Expeccted wrong values {0:x} {1:x}, got: {2:x} {3:x}" -f $correctR,$correctB,$b,$r;
            if ($Force) {
                Write-Warning "$SourcePath : $msg; proceeding anyway due to -Force";
            } else {
                throw "$SourcePath : $msg";
            }
        } 



        $bytesB.CopyTo($ocl, $bytesROffset);
        $bytesR.CopyTo($ocl, $bytesBOffset);
        

        [System.IO.File]::WriteAllBytes($patchedOclFile, $ocl);

        Write-Debug "Patched ocl to $patchedOclFile";



        $tmpOcl = [System.IO.Path]::GetTempFileName();
        cp $patchedOclFile $tmpOcl -Force;
        exiftool "-OpCodeList3<=$tmpOcl" -b -m -n $overwriteOriginal $DestinationPath ;
    }
}

function Foreach-WithProgress {
    [CmdletBinding()]
    param (
        [ScriptBlock] $script,
        [Parameter(ValueFromPipeline)]
        $line,
        [string]$ProgressActivity = "Processing"
    )
    

    $in = $Input;
    $count = $in.Count;

    $in | %{$i=0;}{
        Write-Progress -PercentComplete ($i*100/([float]$count)) -Activity $ProgressActivity;
        Invoke-Command $script;
        $i = $i+1;
    }

}