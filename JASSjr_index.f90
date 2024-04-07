! Copyright (c) 2024 Vaughan Kitchen
! Minimalistic BM25 search engine.

module dynarray_integer_mod
        implicit none
        private

        type, public :: dynarray_integer_class
                integer :: capacity, length
                integer(kind=4), allocatable :: store(:)
        contains
                procedure, public :: init => dynarray_integer_init
                procedure, public :: append => dynarray_integer_append
                procedure, public :: at => dynarray_integer_at
                procedure, public :: inc => dynarray_integer_inc
                procedure, public :: print => dynarray_integer_print
        end type dynarray_integer_class

contains
        subroutine dynarray_integer_init(this)
                class(dynarray_integer_class), intent(inout) :: this

                this%capacity = 128
                this%length = 0
                allocate(this%store(this%capacity))
        end subroutine dynarray_integer_init

        subroutine dynarray_integer_append(this, val)
                class(dynarray_integer_class), intent(inout) :: this
                integer(kind=4), intent(in) :: val
                integer(kind=4), allocatable :: buffer(:)

                if (this%length == this%capacity) then
                        call move_alloc(this%store, buffer)
                        this%capacity = this%capacity * 2
                        allocate(this%store(this%capacity))
                        this%store(1:this%length) = buffer
                        deallocate(buffer)
                end if

                this%length = this%length + 1
                this%store(this%length) = val
        end subroutine dynarray_integer_append

        function dynarray_integer_at(this, i) result(out)
                class(dynarray_integer_class), intent(inout) :: this
                integer, intent(in) :: i
                integer :: out

                if (i < 0) then
                        out = this%store(this%length + 1 + i)
                else
                        out = this%store(i)
                end if
        end function dynarray_integer_at

        subroutine dynarray_integer_inc(this, i)
                class(dynarray_integer_class), intent(inout) :: this
                integer, intent(in) :: i

                if (i < 0) then
                        this%store(this%length + 1 + i) = this%store(this%length + 1 + i) + 1
                else
                        this%store(i) = this%store(i) + 1
                end if
        end subroutine dynarray_integer_inc

        subroutine dynarray_integer_print(this)
                class(dynarray_integer_class), intent(inout) :: this
                integer :: i

                do i = 1, this%length
                        print *, this%store(i)
                end do
        end subroutine dynarray_integer_print
end module dynarray_integer_mod

module dynarray_string_mod
        implicit none
        private

        type, public :: dynarray_string_class
                integer :: capacity, length
                character(len=255), allocatable :: store(:)
        contains
                procedure, public :: init => dynarray_string_init
                procedure, public :: append => dynarray_string_append
                procedure, public :: print => dynarray_string_print
        end type dynarray_string_class

contains
        subroutine dynarray_string_init(this)
                class(dynarray_string_class), intent(inout) :: this

                this%capacity = 128
                this%length = 0
                allocate(this%store(this%capacity))
        end subroutine dynarray_string_init

        subroutine dynarray_string_append(this, val)
                class(dynarray_string_class), intent(inout) :: this
                character(len=*), intent(in) :: val
                character(len=255), allocatable :: buffer(:)

                if (this%length == this%capacity) then
                        call move_alloc(this%store, buffer)
                        this%capacity = this%capacity * 2
                        allocate(this%store(this%capacity))
                        this%store(1:this%length) = buffer
                        deallocate(buffer)
                end if

                this%length = this%length + 1
                this%store(this%length) = val
        end subroutine dynarray_string_append

        subroutine dynarray_string_print(this)
                class(dynarray_string_class), intent(inout) :: this
                integer :: i

                do i = 1, this%length
                        print *, this%store(i)
                end do
        end subroutine dynarray_string_print
end module dynarray_string_mod

module vocab_mod
        use dynarray_integer_mod
        implicit none
        private

        ! Fortran doesn't allow array of pointers
        type :: pair
                character(len=:), allocatable :: term
                type(dynarray_integer_class), pointer :: postings => null()
        end type pair


        type, public :: vocab_class
                integer :: capacity, length
                type(pair), allocatable :: store(:)
        contains
                procedure, public :: init => vocab_init
                procedure, public :: add => vocab_add
                procedure, public :: print => vocab_print
        end type vocab_class

contains
        ! djb2 hash function from http://www.cse.yorku.ca/~oz/hash.html
        function hash(str) result(out)
                character(len=*), intent(in):: str
                integer :: out
                integer :: i

                out = 5381

                do i = 1, len(str)
                        out = ishft(out, 5) + out + ichar(str(i:i)) ! hash * 33 + c
                end do
        end function hash

        subroutine vocab_init(this)
                class(vocab_class) :: this

                this%capacity = 128
                this%length = 0
                allocate(this%store(this%capacity))
        end subroutine vocab_init

        subroutine vocab_add(this, term, docid)
                class(vocab_class), intent(inout) :: this
                character(len=*), intent(in) :: term
                integer, intent(in) :: docid
                integer :: i

                ! TODO expand if full

                i = mod(hash(term), this%capacity) + 1

                do while (associated(this%store(i)%postings))
                        if (this%store(i)%term == term) then
                                if (this%store(i)%postings%at(-2) == docid) then
                                        call this%store(i)%postings%inc(-1)
                                        return
                                end if
                                call this%store(i)%postings%append(docid)
                                call this%store(i)%postings%append(1)
                                return
                        end if
                        i = mod(i + 1, this%capacity) + 1
                end do

                this%store(i)%term = term
                allocate(this%store(i)%postings)
                call this%store(i)%postings%init()
                call this%store(i)%postings%append(docid)
                call this%store(i)%postings%append(1)
        end subroutine vocab_add

        subroutine vocab_print(this)
                class(vocab_class), intent(inout) :: this
                integer :: i

                do i = 1, this%capacity
                        if (associated(this%store(i)%postings)) then
                                print '(A)', this%store(i)%term
                                call this%store(i)%postings%print()
                        end if
                end do
        end subroutine vocab_print
end module vocab_mod

module lexer_mod
        implicit none
        private

        ! Class lexer
        type, public :: lexer_class
                integer :: length, current
                character(len=:), allocatable :: buffer
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
                character(len=*), intent(in) :: buffer

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
        use dynarray_integer_mod
        use dynarray_string_mod
        use lexer_mod
        use vocab_mod
        implicit none

        type(lexer_class) :: lexer
        type(vocab_class) :: vocab
        type(dynarray_string_class) :: doc_ids
        type(dynarray_integer_class) :: length_vector
        integer :: argc, docid, document_length
        integer :: rc ! return code
        logical :: push_next
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

        ! Init
        docid = -1
        document_length = 0
        push_next = .FALSE.
        call vocab%init()
        call doc_ids%init()
        call length_vector%init()

        ! Read the file line by line
        do
                read (10, '(A)', iostat=rc) buffer
                if (rc /= 0) exit
                call lexer%init(buffer)
                ! Read the line token by token
                do
                        token = lexer%get_next(rc)
                        if (rc /= 0) exit
                        ! If we see a <DOC> tag then we're at the start of the next document
                        if (token == '<DOC>') then
                                ! Save the previous document length
                                if (docid /= -1) call length_vector%append(document_length)
                                ! Move on to the next document
                                docid = docid + 1
                                document_length = 0
                                if (mod(docid, 1000) == 0) print '(I0, A)', docid, ' documents indexed'
                        end if
                        ! if the last token we saw was a <DOCNO> then the next token is the primary key
                        if (push_next) then
                                call doc_ids%append(token)
                                push_next = .FALSE.
                        end if
                        if (token == '<DOCNO>') push_next = .TRUE.
                        ! Don't index XML tags
                        if (token(1:1) == '<') cycle
                        ! Lowercase the string
                        call lowercase(token)
                        ! Truncate any long tokens at 255 charactes (so that the length can be stored first and in a single byte)
                        if (len_trim(token) > 255) token = token(1:255)
                        ! Add the posting to the in-memory index
                        call vocab%add(token, docid)
                        ! Compute the document length
                        document_length = document_length + 1
                end do
        end do

        call vocab%print()

        ! Clean up
        close (10)

contains
        subroutine lowercase(str)
                character(len=*), intent(inout) :: str
                integer :: i

                do i = 1, len(str)
                        if ('A' <= str(i:i) .AND. str(i:i) <= 'Z') str(i:i) = char(ichar(str(i:i)) + 32)
                end do
        end subroutine lowercase
end program index
