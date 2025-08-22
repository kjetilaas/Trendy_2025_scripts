#!/bin/bash 

#Scrip to clone, build and run NorESM on Betzy

dosetup1=0 #do first part of setup
dosetup2=1 #do second part of setup (after first manual modifications)
dosetup3=1 #do second part of setup (after namelist manual modifications)
dosubmit=1 #do the submission stage
forcenewcase=0 #scurb all the old cases and start again
numCPUs=0 #Specify number of cpus. 0: use default

echo "setup1, setup2, setup3, submit, forcenewcase:", $dosetup1, $dosetup2, $dosetup3, $dosubmit, $forcenewcase

USER="kjetisaa"
project='nn9188k' #nn8057k: EMERALD, nn2806k: METOS, nn9188k: CICERO, nn9560k: NorESM (INES2), nn9039k: NorESM (UiB: Climate predition unit?), nn2345k: NorESM (EU projects)
machine='betzy'

#NorESM dir
noresmrepo="ctsm5.3.045_noresm_v10" 
noresmversion="ctsm5.3.045_noresm_v10"

resolution="f19_g17" #f19_g17, ne30pg3_tn14, f45_f45_mg37, ne16pg3_tn14, hcru_hcru_mt13
casename="i1700.$resolution.fatesnocomp.$noresmversion.PostADspinup_TRENDY2025.20250816" 

compset="1850_DATM%TRENDY25_CLM60%FATES_SICE_SOCN_SROF_SGLC_SWAV_SESP"

# aka where do you want the code and scripts to live?
workpath="/cluster/work/users/$USER/" 

# some more derived path names to simplify scripts
scriptsdir=$workpath$noresmrepo/cime/scripts/

#case dir
casedir=$workpath$casename

#where are we now?
startdr=$(pwd)

#Download code and checkout externals
if [ $dosetup1 -eq 1 ] 
then
    cd $workpath

    pwd
    #go to repo, or checkout code
    if [[ -d "$noresmrepo" ]] 
    then
        cd $noresmrepo
        echo "Already have NorESM repo"
    else
        echo "Cloning NorESM"
        
        if [[ $noresmversion == ctsm* ]] ; then
            echo "Using CTSM version $noresmversion"
            git clone https://github.com/NorESMhub/CTSM/ $noresmrepo
        else
            echo "Using NorESM version $noresmversion"
            git clone https://github.com/NorESMhub/NorESM/ $noresmrepo
        fi
        cd $noresmrepo
        git checkout $noresmversion
        ./bin/git-fleximod update
        echo "Built model here: $workpath$noresmrepo"        

    fi
fi

#Make case
if [[ $dosetup2 -eq 1 ]] 
then
    cd $scriptsdir

    if [[ $forcenewcase -eq 1 ]]
    then 
        if [[ -d "$workpath$casename" ]] 
        then    
        echo "$workpath$casename exists on your filesystem. Removing it!"
        rm -rf $workpath$casename
        rm -r $workpath/noresm/$casename
        rm -r $workpath/archive/$casename
        rm -r $casename
        fi
    fi
    if [[ -d "$workpath$casename" ]] 
    then    
        echo "$workpath$casename exists on your filesystem."
    else
        echo "making case:" $workpath$casename
        ./create_newcase --case $workpath$casename --compset $compset --res $resolution --project $project --run-unsupported --mach betzy  --pecount L #From create_newcase.py: Allowed options are  ('S','M','L','X1','X2','[0-9]x[0-9]','[0-9]').
        cd $workpath$casename

        #XML changes
        echo 'updating settings'        
        ./xmlchange DIN_LOC_ROOT_CLMFORC=/cluster/work/users/kjetisaa/Trendy_2025_forcing/
        ./xmlchange STOP_OPTION=nyears
        ./xmlchange STOP_N=100 
        ./xmlchange RESUBMIT=2 
        ./xmlchange --subgroup case.run JOB_WALLCLOCK_TIME=36:00:00
        ./xmlchange --subgroup case.st_archive JOB_WALLCLOCK_TIME=00:30:00    
        ./xmlchange RUN_STARTDATE=0201-01-01
        ./xmlchange CLM_ACCELERATED_SPINUP=off    
        ./xmlchange CCSM_CO2_PPMV=277.57
        ./xmlchange CLM_CO2_TYPE=constant        
        ./xmlchange DATM_YR_START=1901
        ./xmlchange DATM_YR_ALIGN=1
        ./xmlchange DATM_YR_END=1920
        ./xmlchange DATM_PRESAERO=clim_1850            

        if [[ $numCPUs -ne 0 ]]
        then 
            echo "setting #CPUs to $numCPUs"
            ./xmlchange NTASKS_ATM=$numCPUs
            ./xmlchange NTASKS_OCN=$numCPUs
            ./xmlchange NTASKS_LND=$numCPUs
            ./xmlchange NTASKS_ICE=$numCPUs
            ./xmlchange NTASKS_ROF=$numCPUs
            ./xmlchange NTASKS_GLC=$numCPUs
        fi

        echo 'done with xmlchanges'        
        
        ./case.setup
        echo ' '
        echo "Done with Setup. Update namelists in $workpath$casename/user_nl_*"

        #Add following lines to user_nl_clm    
        echo "use_fates_nocomp=.true." >> $workpath$casename/user_nl_clm
        echo "use_fates_fixed_biogeog=.true." >> $workpath$casename/user_nl_clm

        echo "use_fates_luh = .true." >> $workpath$casename/user_nl_clm
        echo "use_fates_lupft = .true." >> $workpath$casename/user_nl_clm
        echo "fates_harvest_mode = 'luhdata_area'" >> $workpath$casename/user_nl_clm
        echo "use_fates_potentialveg = .false." >> $workpath$casename/user_nl_clm
        echo "fluh_timeseries = '/cluster/work/users/kjetisaa/Trendy_2025_forcing/LUH3/Lowres/LUH2_states_transitions_management.timeseries_1.9x2.5_hist_steadystate_1700_2025-07-23_cdf5.nc'" >> $workpath$casename/user_nl_clm                        
        echo "flandusepftdat = '/cluster/work/users/kjetisaa/Trendy_2025_forcing/LUH3/Lowres/fates_landuse_pft_map_to_surfdata_1.9x2.5_250723_cdf5.nc'" >> $workpath$casename/user_nl_clm                
        echo "fates_spitfire_mode = 1" >> $workpath$casename/user_nl_clm
        echo "fates_paramfile = '/cluster/shared/noresm/inputdata/lnd/clm2/paramdata/fates_params_api.40.0.0_14pft_c250807_noresm_v24.nc'" >> $workpath$casename/user_nl_clm        

        echo "hist_empty_htapes = .true." >> $workpath$casename/user_nl_clm
        echo "hist_fincl1 = 'TOTECOSYSC', 'TOTSOMC', 'TOTSOMC_1m', 'FATES_NONSTRUCTC', 'FATES_STRUCTC', 'TOTCOLC', 'TLAI', 'FATES_GPP', 'FCO2', 'FATES_NEP', 'FATES_NPP', 'TWS', 'H2OSNO', 'FSNO', 'FATES_LITTER_AG_CWD_EL', 'FATES_LITTER_AG_FINE_EL', 'FATES_LITTER_BG_CWD_EL', 'FATES_LITTER_BG_FINE_EL'" >> $workpath$casename/user_nl_clm
        echo "hist_mfilt = 10" >> $workpath$casename/user_nl_clm
        echo "hist_nhtfrq = -8760" >> $workpath$casename/user_nl_clm    
        echo "finidat = '/cluster/home/kjetisaa/Trendy_2025_scripts/Restarts/i1700.f19_g17.fatesnocomp.ctsm5.3.045_noresm_v10.ADspinup_TRENDY2025.20250813.clm2.r.0201-01-01-00000.nc' " >> user_nl_clm
    fi
fi

#Build case case
if [[ $dosetup3 -eq 1 ]] 
then
    cd $workpath$casename
    echo "Currently in" $(pwd)
    ./case.build
    echo ' '    
    echo "Done with Build"
fi

#Submit job
if [[ $dosubmit -eq 1 ]] 
then
    cd $workpath$casename
    ./case.submit
    echo " "
    echo 'done submitting'       
fi

#After it has finised:
# - copy to NIRD: https://noresm-docs.readthedocs.io/en/noresm2/output/archive_output.html
# - run land diag: https://github.com/NorESMhub/xesmf_clm_fates_diagnostic 
    # python run_diagnostic_full_from_terminal.py /nird/datalake/NS9560K/kjetisaa/i1850.FATES-NOCOMP-coldstart.ne30pg3_tn14.alpha08d.20250130/lnd/hist/ pamfile=short_nocomp.json outpath=/datalake/NS9560K/www/diagnostics/noresm/kjetisaa/
#Useful commands: 
# - cdo -fldmean -mergetime -apply,selvar,FATES_GPP,TOTSOMC,TLAI,TWS,TOTECOSYSC [ n1850.FATES-NOCOMP-AD.ne30_tn14.alpha08d.20250127_fixFincl1.clm2.h0.00* ] simple_mean_of_gridcells.nc