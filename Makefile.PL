use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME         => 'Net::Server::POP3',
    VERSION_FROM => 'lib/Net/Server/POP3.pm', # finds $VERSION
    AUTHOR       => 'Jonadab the Unsightly One (Nathan Eady) (jonadab@bright.net)',
    ABSTRACT     => '',
    PREREQ_PM    => {
                     'Test::Simple' => 0.44,
                    },
);
