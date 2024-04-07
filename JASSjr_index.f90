module lexer_mod
        implicit none
        private

        ! Class lexer
        type, public :: lexer_class
                character(len=:), allocatable :: buffer
                integer :: current
                integer :: length
        contains
                procedure, public :: init => lexer_init
                procedure, public :: get_next => lexer_get_next
        end type lexer_class

contains
        function is_alnum(c) result(out)
                character(len=1), intent(in) :: c
                logical :: out

                select case (ichar(c))
                        case (48:57) ! numeric
                                out = .TRUE.
                        case (65:90) ! capital letters
                                out = .TRUE.
                        case (97:122) ! lowercase letters
                                out = .TRUE.
                        case default
                                out = .FALSE.
                end select
        end function is_alnum

        subroutine lexer_init(this, buffer)
                class(lexer_class), intent(inout) :: this
                character(len=*) :: buffer

                this%buffer = buffer
                this%current = 1
                this%length = len_trim(buffer)
        end subroutine lexer_init

        ! One-character lookahead lexical analyser
        function lexer_get_next(this, rc) result(out)
                class(lexer_class), intent(inout) :: this
                integer, intent(inout) :: rc
                character(len=:), allocatable :: out
                integer :: start

                ! Skip over whitespace and punctuation (but not XML tags)
                do while (this%current <= this%length .AND. .NOT. is_alnum(this%buffer(this%current:this%current)) &
                .AND. this%buffer(this%current:this%current) /= '<')
                        this%current = this%current + 1
                end do

                ! A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
                start = this%current
                if (this%current > this%length) then
                        rc = -1
                        return
                else if (is_alnum(this%buffer(this%current:this%current))) then
                        do while (this%current <= this%length .AND. (is_alnum(this%buffer(this%current:this%current)) &
                        .OR. this%buffer(this%current:this%current) == '-'))
                                this%current = this%current + 1
                        end do
                else if (this%buffer(this%current:this%current) == '<') then
                        this%current = this%current + 1
                        do while (this%current <= this%length .AND. this%buffer(this%current-1:this%current-1) /= '>')
                                this%current = this%current + 1
                        end do
                end if

                ! Copy and return the token
                out = this%buffer(start:this%current-1)
        end function lexer_get_next
end module lexer_mod

program index
        use lexer_mod
        implicit none

        type(lexer_class) :: lexer
        integer :: rc ! return code
        integer :: argc
        character(len=1024 * 1024) :: buffer
        character(len=:), allocatable :: token

        ! Make sure we have one parameter, the filename
        argc = command_argument_count()
        if (argc /= 1) then
                call get_command_argument(0, buffer)
                print '(A)', 'Usage: ' // buffer(1:len_trim(buffer)) // ' <infile.xml>'
                stop
        end if

        ! Open the file to index
        call get_command_argument(1, buffer)
        open (action='read', file=buffer(1:len_trim(buffer)), iostat=rc, unit=10)
        if (rc /= 0) stop 'ERROR: open failed'

        do
                read (10, '(A)', iostat=rc) buffer
                if (rc /= 0) exit
                call lexer%init(buffer)
                do
                        token = lexer%get_next(rc)
                        if (rc /= 0) exit
                        print '(A)', token
                end do
        end do

        ! Clean up
        close (10)
end program index
