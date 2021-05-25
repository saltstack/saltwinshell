# -*- coding: utf-8 -*-
'''
Core functions to impliment the salt windows shell
'''
# Copyright 2021 VMware, Inc.
# SPDX-License-Identifier: Apache-2.0
from __future__ import absolute_import

import os
import logging
import salt.exceptions
import salt.ext.six
import salt.utils.smb
try:
    import salt.utils.stringutils as stringutils
except ImportError:
    # This exception handling can be removed once 2017.7 is no longer
    # supported.
    import salt.utils as stringutils
from salt.client.ssh.shell import Shell as LinuxShell
import ntpath
from saltwinshell.version import version as version

# Import 3rd party libs
try:
    from winrm.protocol import Protocol
    HAS_WINRM = True
except Exception:
    HAS_WINRM = False

log = logging.getLogger(__name__)

# Windows Powershell Shim - actually, this is python
SSH_PS_SHIM =  \
        '\n'.join(
            [s.strip() for s in r'''
import base64

exec(base64.b64decode("""{SSH_PY_CODE}"""))
'''.split('\n')])


def set_winvars(self, ssh_python_env=None):
    '''
    Set the Win Vars
    '''
    self.thin_dir = 'c:\\saltremote/thin'
    self.python_dir = 'c:\\saltremote/bin'
    pyver = 'Py3'
    if salt.ext.six.PY2:
        pyver = 'Py2'
    self.python_env_map = {
            'AMD64': 'Salt-Env-{0}-AMD64-{1}.zip'.format(version, pyver),
            'x86'  : 'Salt-Env-{0}-x86-{1}.zip'.format(version, pyver),
            }
    self.python_saltwinshell = '/usr/local/saltwinshell'
    if os.path.exists('/usr/saltwinshell'):
        self.python_saltwinshell = '/usr/saltwinshell'


def gen_shim(py_code_enc):
    '''
    Generate a PowerShell shim
    '''
    cmd = SSH_PS_SHIM.format(SSH_PY_CODE=py_code_enc)
    return cmd


def get_target_shim_file(self, target_shim_file):
    '''
    Get the target shim file
    '''
    return ntpath.normpath(ntpath.sep.join((self.python_dir, target_shim_file)))


def call_python(self, target_shim_file):
    '''
    Call python stuff
    '''
    return self.shell.exec_cmd('{0} {1}'.format(ntpath.normpath(ntpath.sep.join((self.python_dir, 'python.exe'))), ntpath.normpath(target_shim_file)))


def deploy_python(self):
    '''
    Deploy the Windows python environment
    '''
    if not self.python_env:
        log.debug('No Python Environment found. Determining which env to use')
        self.python_env = os.path.join(self.python_saltwinshell, self.python_env_map[self.arch])
        if not os.path.isfile(self.python_env):
            if os.path.isfile(os.path.join(self.python_saltwinshell, self.python_env_map[self.arch])):
                self.python_env = os.path.join(self.python_saltwinshell, self.python_env_map[self.arch])
        if not os.path.isfile(self.python_env):
            raise salt.exceptions.SaltConfigurationError( 'Python env: {0} doesn\'t exist.'.format(self.python_env))
    self.shell.send(
        self.python_env,
        os.path.join(self.python_dir, 'bin.zip'),
        makedirs=True,
    )
    self.shell.send(
        os.path.join(self.python_saltwinshell, 'Synchronous-ZipAndUnzip.psm1'),
        os.path.join(self.python_dir, 'Synchronous-ZipAndUnzip.psm1'),
        makedirs=True,
    )
    UNZIP_SHIM = '''
$THIS_SCRIPTS_DIRECTORY_PATH = '{0}'
$SynchronousZipAndUnzipModulePath = Join-Path $THIS_SCRIPTS_DIRECTORY_PATH 'Synchronous-ZipAndUnzip.psm1'
Import-Module -Name $SynchronousZipAndUnzipModulePath

# Variables used to test the functions.
$zipFilePath = "{1}";
$destinationDirectoryPath = "{2}";

# Unzip the Zip file to a new UnzippedContents directory.
Expand-ZipFile -ZipFilePath $zipFilePath -DestinationDirectoryPath $destinationDirectoryPath -OverwriteWithoutPrompting
'''.format(ntpath.normpath(self.python_dir), ntpath.normpath(ntpath.join(self.python_dir, 'bin.zip')), ntpath.normpath(self.python_dir))
    stdout, stderr, retcode = self.shim_cmd(UNZIP_SHIM, extension='ps1')
    return True


class Shell(LinuxShell):
    def send(self, local, remote, makedirs=False):
        '''
        send a file to a remote system using smb
        '''
        ret_stdout = ret_stderr = retcode = None
        if makedirs:
            self.exec_cmd('mkdir {0}'.format(ntpath.dirname(ntpath.normpath(remote))))

        smb_conn = salt.utils.smb.get_conn(self.host, self.user, self.passwd)
        if smb_conn is False:
            ret_stderr = 'Please install impacket to enable SMB functionality'
            log.error(ret_stderr)
            return ret_stdout, ret_stderr, 1

        log.debug('Copying {0} to {1} on minion'.format(local, ntpath.normpath(remote)))
        if remote.startswith('c:'):
            drive, remote = remote.split(':')
        salt.utils.smb.put_file(local, ntpath.normpath(remote), conn=smb_conn)
        retcode = 0

        return ret_stdout, ret_stderr, retcode

    def exec_cmd(self, cmd):
        '''
        Execute a remote command
        '''
        logmsg = 'Executing command: {0}'.format(cmd)
        if self.passwd:
            logmsg = logmsg.replace(self.passwd, ('*' * 6))
        if 'decode("base64")' in logmsg or 'base64.b64decode(' in logmsg:
            log.debug('Executed SHIM command. Command logged to TRACE')
            log.trace(logmsg)
        else:
            log.debug(logmsg)

        ret = self._run_cmd(cmd)
        return ret

    def _run_cmd(self, cmd, key_accept=False, passwd_retries=3):
        '''
        Execute a shell command via PowerShell.
        '''
        if not HAS_WINRM:
            return None, 'pywinrm is required to be installed on the Salt Master', 1

        p = Protocol(
                endpoint='https://{0}:5986/wsman'.format(self.host),
                transport='ntlm',
                username=self.user,
                password=self.passwd,
                server_cert_validation='ignore')
        shell_id = p.open_shell()
        command_id = p.run_command(shell_id, cmd)
        std_out_bytes, std_err_bytes, status_code = p.get_command_output(shell_id, command_id)
        p.cleanup_command(shell_id, command_id)
        p.close_shell(shell_id)
        std_out = stringutils.to_unicode(std_out_bytes)
        std_err = stringutils.to_unicode(std_err_bytes)
        return std_out, std_err, status_code

