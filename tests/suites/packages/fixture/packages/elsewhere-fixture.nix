# Built for no real system: left out of packages.<system>, still in pkgs.
{writeText}: (writeText "elsewhere-fixture" "") // {meta.platforms = ["mmix-mmixware"];}
