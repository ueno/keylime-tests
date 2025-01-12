#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
. /usr/share/beakerlib/beakerlib.sh || exit 1

AGENT_ID="d432fbb3-d2f1-4a97-9ef7-75bd81c00000"

rlJournalStart

    rlPhaseStartSetup "Do the keylime setup"
        rlRun 'rlImport "./test-helpers"' || rlDie "cannot import keylime-tests/test-helpers library"
        rlAssertRpm keylime
        limeBackupConfig
        # update /etc/keylime.conf
        rlRun "limeUpdateConf tenant require_ek_cert False"
        # if TPM emulator is present
        if limeTPMEmulated; then
            # start tpm emulator
            rlRun "limeStartTPMEmulator"
            rlRun "limeWaitForTPMEmulator"
            # make sure tpm2-abrmd is running
            rlServiceStart tpm2-abrmd
            sleep 5
            # start ima emulator
            rlRun "limeInstallIMAConfig"
            rlRun "limeStartIMAEmulator"
        fi
        sleep 5
        # start keylime_verifier
        rlRun "limeStartVerifier"
        rlRun "limeWaitForVerifier"
        rlRun "limeStartRegistrar"
        rlRun "limeWaitForRegistrar"
        rlRun "limeStartAgent"
        rlRun "limeWaitForAgentRegistration ${AGENT_ID}"
        # create allowlist and excludelist
        limeCreateTestLists
    rlPhaseEnd

    rlPhaseStartTest "-c add"
        rlRun "lime_keylime_tenant -v 127.0.0.1 -t 127.0.0.1 -u $AGENT_ID --allowlist allowlist.txt --exclude excludelist.txt -f excludelist.txt -c add"
        rlRun "limeWaitForAgentStatus $AGENT_ID 'Get Quote'"
    rlPhaseEnd

    rlPhaseStartTest "-c cvlist"
        rlRun -s "lime_keylime_tenant -c cvlist"
        rlAssertGrep "{'code': 200, 'status': 'Success', 'results': {'uuids':.*'$AGENT_ID'" $rlRun_LOG
    rlPhaseEnd

    rlPhaseStartTest "-c cvstatus"
        rlRun -s "lime_keylime_tenant -c cvstatus"
        rlAssertGrep "{\"$AGENT_ID\": {\"operational_state\": \"(Get Quote|Provide V)\"" $rlRun_LOG -E
    rlPhaseEnd

    rlPhaseStartTest "-c reglist"
        rlRun -s "lime_keylime_tenant -c reglist"
        rlAssertGrep "{\"code\": 200, \"status\": \"Success\", \"results\": {\"uuids\":.*\"$AGENT_ID\"" $rlRun_LOG
    rlPhaseEnd

    rlPhaseStartTest "-c regstatus"
        rlRun -s "lime_keylime_tenant -c regstatus"
        rlAssertGrep "{\"code\": 200, \"status\": \"Agent $AGENT_ID exists on registrar 127.0.0.1 port 8891.\"" $rlRun_LOG
    rlPhaseEnd
 
    rlPhaseStartTest "-c status"
        rlRun -s "lime_keylime_tenant -c status"
        rlAssertGrep "{\"code\": 200, \"status\": \"Agent $AGENT_ID exists on registrar 127.0.0.1 port 8891.\"" $rlRun_LOG
        rlAssertGrep "{\"$AGENT_ID\": {\"operational_state\": \"(Get Quote|Provide V)\"" $rlRun_LOG -E
    rlPhaseEnd
 
    rlPhaseStartTest "-c bulkinfo"
        rlRun -s "lime_keylime_tenant -c bulkinfo"
        rlAssertGrep "INFO - Bulk Agent Info:" $rlRun_LOG
        rlAssertGrep "{\"$AGENT_ID\": {\"operational_state\": \"(Get Quote|Provide V)\"" $rlRun_LOG -E
    rlPhaseEnd

    rlPhaseStartTest "Fail keylime agent"
        TESTDIR=`limeCreateTestDir`
        rlRun "echo -e '#!/bin/bash\necho boom' > $TESTDIR/keylime-bad-script.sh && chmod a+x $TESTDIR/keylime-bad-script.sh"
        rlRun "$TESTDIR/keylime-bad-script.sh"
        rlRun "limeWaitForAgentStatus $AGENT_ID '(Failed|Invalid Quote)'"
        rlAssertGrep "WARNING - File not found in allowlist: $TESTDIR/keylime-bad-script.sh" $(limeVerifierLogfile)
        rlAssertGrep "WARNING - Agent $AGENT_ID failed, stopping polling" $(limeVerifierLogfile)
	limeExtendNextExcludelist $TESTDIR
    rlPhaseEnd

    rlPhaseStartTest "-c update"
        # create new allowlist and excludelist
        limeCreateTestLists
        rlRun "lime_keylime_tenant -v 127.0.0.1 -t 127.0.0.1 -u $AGENT_ID --allowlist allowlist.txt --exclude excludelist.txt -f excludelist.txt -c update"
        rlRun "limeWaitForAgentStatus $AGENT_ID 'Get Quote'"
    rlPhaseEnd

    rlPhaseStartTest "-c reactivate"
        rlRun -s "lime_keylime_tenant -c reactivate"
        rlAssertGrep "{\"$AGENT_ID\": {\"operational_state\": \"(Get Quote|Provide V)\"" $rlRun_LOG -E
        rlAssertGrep "INFO - Agent $AGENT_ID re-activated" $rlRun_LOG
    rlPhaseEnd

    rlPhaseStartTest "-c regdelete"
        rlRun -s "lime_keylime_tenant -c regdelete"
        rlRun -s "lime_keylime_tenant -c regstatus"
        rlAssertGrep "{\"code\": 404, \"status\": \"Agent $AGENT_ID does not exist on registrar 127.0.0.1 port 8891.\"" $rlRun_LOG
    rlPhaseEnd
 
    rlPhaseStartTest "-c delete"
        rlRun -s "lime_keylime_tenant -c delete"
        rlAssertGrep "INFO - CV completed deletion of agent $AGENT_ID" $rlRun_LOG
        rlRun -s "lime_keylime_tenant -c cvstatus"
        rlAssertGrep "Verifier at 127.0.0.1 with Port 8881 does not have agent $AGENT_ID" $rlRun_LOG
    rlPhaseEnd
 
    # TODO
    # -c addallowlist
    # -c showallowlist
    # -c deleteallowlist

    rlPhaseStartCleanup "Do the keylime cleanup"
        rlRun "limeStopAgent"
        rlRun "limeStopRegistrar"
        rlRun "limeStopVerifier"
        limeLogfileSubmit $(limeVerifierLogfile)
        limeLogfileSubmit $(limeRegistrarLogfile)
        limeLogfileSubmit $(limeAgentLogfile)
        if limeTPMEmulated; then
            rlRun "limeStopIMAEmulator"
            limeLogfileSubmit $(limeIMAEmulatorLogfile)
            rlRun "limeStopTPMEmulator"
            rlServiceRestore tpm2-abrmd
        fi
        limeClearData
        limeRestoreConfig
        limeExtendNextExcludelist $TESTDIR
        #rlRun "rm -f $TESTDIR/keylime-bad-script.sh"  # possible but not really necessary
    rlPhaseEnd

rlJournalEnd
