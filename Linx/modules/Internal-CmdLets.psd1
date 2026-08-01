@{
    ModuleVersion = '1.0'
    GUID          = '3c709be6-28c7-0000-1111-9004092ecfec'
    Author        = 'Fredrik Bergman'
    CompanyName   = 'Swedish Prosecution Authority'

    # The primary module file
    RootModule    = 'Internal-Cmdlets.psm1'

    # Modules to import as nested modules of the root module
    NestedModules = @('..\..\RestPSModule\RestPSCustomModule.psm1')

    # Ensure functions from both are available to the caller
    FunctionsToExport = '*'
    CmdletsToExport   = '*'
    VariablesToExport = '*'
    AliasesToExport   = '*'
}