// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.10;
pragma experimental ABIEncoderV2;

//import './Utility.sol';
import './Airline.sol';
import './Ticket.sol';

contract BookingServer {
    address[] airlines;

    event TicketBookEvent (
      address TicketAddress
    );
    event RevertEvent (
      string ErrorMessage
    );
    event TicketCancelEvent (
      uint timeDifference,
      bool isAfterDepartureflag,
      uint penaltyPercentage
    );
    
    constructor() {
    }
    // BookingServer is an integrator where multiple airlines could be associated
    // This is the first function that need to be called before any booking can be done 
    function registerAirline(address _airLineAddress) public returns(address AirlineContractAccount, string memory AirlineName){
        //Airline airline = Airline(_airLineAddress);
        airlines.push(payable(_airLineAddress));
        return(Airline(payable(airlines[0])).getAddress()); 
    }
    //This is to get the AirlineDetails 
    //TBD-P4: NICE TO HAVE: Support multiple airlines related changes  
    function getAirlineDetails() public view returns(address AirlineAccount, string memory AirlineName){
        return(Airline(payable(airlines[0])).getAddress()); 
    }
    //This is to get all the Operable flights 
    //TBD-P4: NICE TO HAVE: Support multiple airlines related changes
    function getOperableFlights() view public returns (string memory){
        return Airline(payable(airlines[0])).getOperableFlights();
    }
    //This is to book tickets in the available flights
    function bookTicket(string memory _flightID,uint8 seats, string memory _myReference) public payable returns(address TicketAddress) {
       if(msg.value == 0){
            emit RevertEvent("**  Error  ** : Please transfer money Booking server");
            revert("**  Error  ** : Please transfer money Booking server");
      }
       address ticketAddress = Airline(payable(airlines[0])).bookTicket(msg.sender,_flightID, seats, msg.value, _myReference);
       transferFromCustomerToTicket(ticketAddress,msg.value);
       emit TicketBookEvent(ticketAddress);
       return ticketAddress;
    }
    // This is to transfer the money to the Ticket from the customer account 
    function transferFromCustomerToTicket(address _ticketAddress, uint _weiValue) internal returns(uint TransferedWeiAmount){
        address payable receiver = payable(_ticketAddress);
        receiver.transfer(_weiValue);
        return _weiValue;
    } 
    function customerCancelTicket(address _ticketAddress) public returns(uint requestTime,bool AfterDepartureflag, uint penaltyPercentage){
        Ticket ticket = Ticket(payable(_ticketAddress));
        if(ticket.getTicketStatus() == 3 || ticket.getTicketStatus() == 4 || ticket.getTicketStatus() == 5){
               emit RevertEvent("** Error **: Ticket is already in status status in FlightCancelled, Completed,CancelledByCustomer status");
               revert("** Error **: Ticket is already in status status in FlightCancelled, Completed,CancelledByCustomer status");
         }
        uint timeNow = block.timestamp;
        uint timeDifference;
        uint departureTime = ticket.getDepartureTime();
        bool isAfter = false;  
        //Canceling before the departure time 
        if( departureTime > timeNow){
            timeDifference = departureTime - timeNow; 
        }
        else{
            //Canceling after the departure time
            timeDifference = timeNow - departureTime;
            isAfter = true; 
        }  
        uint penalty = Airline(payable(airlines[0])).customerCancelTicket(_ticketAddress,timeDifference, isAfter);
        emit TicketCancelEvent(timeDifference, isAfter, penalty);
        return (timeDifference, isAfter, penalty);
    }
    // This function is for testing the different penalities while cancelling and customer claim after 24 hours use cases
    // Anchors scheduled departure time if present(after the flight is updated ontime) or scheduled departure time (Afer flight isupdated ontime)
    // Time difference is calculated from the above based on the input parameter
    function simulateCancelSpecifyingTime(address _ticketAddress, uint _afterDepartureInHours, uint _beforeDepartureInHours) public returns(uint requestTime,bool AfterDepartureflag, uint penaltyPercentage)  {
        Ticket ticket = Ticket(payable(_ticketAddress));
        if(ticket.getTicketStatus() == 3 || ticket.getTicketStatus() == 4 || ticket.getTicketStatus() == 5){
               emit RevertEvent("** Error **: Ticket is already in status status in FlightCancelled, Completed,CancelledByCustomer status");
               revert("** Error **: Ticket is already in status status in FlightCancelled, Completed,CancelledByCustomer status");
         }
        uint timeDifference;
        bool isAfter;
        if(_afterDepartureInHours > 0){
           timeDifference = _afterDepartureInHours*60*60;
           isAfter = true;     
        }
        else{
           timeDifference = _beforeDepartureInHours*60*60;
           isAfter = false;
        }
        uint penalty = Airline(payable(airlines[0])).customerCancelTicket(_ticketAddress,timeDifference,isAfter);
        emit TicketCancelEvent(timeDifference, isAfter, penalty);
        return (timeDifference,isAfter,penalty);
    }
    function getTicketDetails(address _ticketAddress) public view returns(address TicketAddress,string memory FlightID,string memory BookinfReference, uint NumberofSeats, uint ticketFare,uint scheduledDeparture,uint actualDeparture,uint TicketStatus){
        return(Ticket(payable(_ticketAddress)).getTicketDetails());
    }
    function getTicketBalance(address _ticketAddress)public view returns(uint AmountHeldByTicket){
        
        return(_ticketAddress.balance);
    }
    function giveCustomerBalance() public view returns(uint CustomerBalance){
        return(msg.sender.balance);
    }
}
